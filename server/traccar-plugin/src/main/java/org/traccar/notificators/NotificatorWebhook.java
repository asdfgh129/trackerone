/*
 * TrackerOne · Traccar Webhook Notificator
 *
 * 作用：把 Traccar 事件以 HTTP POST 推送到自建推送网关（中国大陆推送链路）。
 *
 * 说明：
 * - 本文件是 Traccar 6.16 的**插件补丁**，不属于 trackerone Flutter 工程；
 * - Traccar 没有通用 webhook 通知器，必须新增 notificator 并在
 *   `NotificatorManager.NOTIFICATORS_ALL` 注册；
 * - 许可证与 Traccar 一致：Apache-2.0。
 */
package org.traccar.notificators;

import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.traccar.config.Config;
import org.traccar.model.Device;
import org.traccar.model.Event;
import org.traccar.model.Position;
import org.traccar.model.User;
import org.traccar.notification.NotificationFormatter;
import org.traccar.notification.NotificationMessage;
import org.traccar.session.cache.CacheManager;

/**
 * 把事件推送到自建网关（网关再调用极光 / 厂商通道）。
 *
 * 配置（traccar.xml）：
 * <pre>
 * &lt;entry key='notificator.types'&gt;web,mail,webhook&lt;/entry&gt;
 * &lt;entry key='notificator.webhook.url'&gt;https://push.example.com/v1/events&lt;/entry&gt;
 * &lt;entry key='notificator.webhook.inboxUrl'&gt;https://push.example.com/v1/messages&lt;/entry&gt;
 * &lt;entry key='notificator.webhook.inboxTypes'&gt;commandResult&lt;/entry&gt;
 * &lt;entry key='notificator.webhook.serverId'&gt;1&lt;/entry&gt;
 * &lt;entry key='notificator.webhook.secret'&gt;请替换为随机密钥&lt;/entry&gt;
 * &lt;entry key='notificator.webhook.timeoutSeconds'&gt;5&lt;/entry&gt;
 * </pre>
 *
 * 指令结果（`commandResult`）默认写入收件箱（`/v1/messages`），
 * 使用同一个 webhook secret 做 HMAC 签名；其余事件仍走 `/v1/events`。
 * 未配置 `inboxUrl` 时按 `url` 自动推导（`/v1/events` → `/v1/messages`）。
 *
 * 签名：`X-Traccar-Signature: sha256=<hex(hmac_sha256(body, secret))>`
 */
@Singleton
public class NotificatorWebhook extends Notificator {

    private static final Logger LOGGER = LoggerFactory.getLogger(NotificatorWebhook.class);

    private final Config config;
    private final CacheManager cacheManager;
    private final ObjectMapper objectMapper;
    private final HttpClient httpClient;

    @Inject
    public NotificatorWebhook(
            Config config, NotificationFormatter notificationFormatter,
            CacheManager cacheManager, ObjectMapper objectMapper) {
        super(notificationFormatter);
        this.config = config;
        this.cacheManager = cacheManager;
        this.objectMapper = objectMapper;
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(5))
                .build();
    }

    @Override
    public CompletableFuture<Void> sendAsync(
            User user, NotificationMessage message, Event event, Position position) {

        String url = config.getString("notificator.webhook.url");
        if (url == null || url.isBlank()) {
            return CompletableFuture.failedFuture(
                    new IllegalStateException("notificator.webhook.url is not configured"));
        }

        try {
            long timeoutSeconds = parseLong(
                    config.getString("notificator.webhook.timeoutSeconds"), 5L);

            // 指令结果等事件写入收件箱：推送只带 inboxId，详情由 App 拉取。
            if (isInboxEvent(event.getType())) {
                String inboxUrl = resolveInboxUrl(url);
                if (inboxUrl != null && !inboxUrl.isBlank()) {
                    return postInboxMessage(inboxUrl, user, message, event, position, timeoutSeconds);
                }
                LOGGER.warn(
                        "notificator.webhook.inboxUrl is not resolvable, "
                                + "falling back to event webhook for {}",
                        event.getType());
            }

            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("version", 1);
            payload.put("userId", user.getId());
            payload.put("userEmail", user.getEmail());
            payload.put("deviceId", event.getDeviceId());

            Device device = cacheManager.getObject(Device.class, event.getDeviceId());
            if (device != null) {
                payload.put("deviceName", device.getName());
                payload.put("uniqueId", device.getUniqueId());
            }

            payload.put("event", event);
            payload.put("position", position);

            Map<String, Object> text = new LinkedHashMap<>();
            text.put("title", message.subject());
            text.put("body", message.body());
            text.put("digest", message.digest());
            payload.put("message", text);
            payload.put("issuedAt", System.currentTimeMillis());

            String body = objectMapper.writeValueAsString(payload);
            return post(url, body, timeoutSeconds, event.getId(), user.getId());

        } catch (Exception error) {
            LOGGER.warn("Webhook delivery failed for event {}", event.getId(), error);
            return CompletableFuture.failedFuture(error);
        }
    }

    /**
     * 把指令结果写入网关收件箱。
     *
     * 载荷字段与 `POST /v1/messages` 契约一致；使用现有 webhook secret 做 HMAC 签名，
     * 因此 Traccar 侧不需要配置管理令牌。
     */
    private CompletableFuture<Void> postInboxMessage(
            String inboxUrl, User user, NotificationMessage message, Event event,
            Position position, long timeoutSeconds) throws Exception {

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("eventType", event.getType());
        data.put("eventId", event.getId());
        data.put("deviceId", event.getDeviceId());

        String result = extractResult(event, position);
        if (!result.isBlank()) {
            data.put("result", result);
            data.put("success", isSuccess(result));
        }

        String body = result;
        if (body.isBlank()) {
            body = message.body();
        }
        if (body == null || body.isBlank()) {
            body = "设备已返回指令结果";
        }

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("userId", user.getId());
        payload.put("serverId", parseLong(
                config.getString("notificator.webhook.serverId"), 1L));
        payload.put("kind", "notice");
        // 标题由 App 按事件类型本地化，避免服务端写死中文。
        payload.put("title", "");
        payload.put("body", body);
        payload.put("data", data);
        payload.put("expiresIn", 7 * 24 * 3600L);

        String encoded = objectMapper.writeValueAsString(payload);
        return post(inboxUrl, encoded, timeoutSeconds, event.getId(), user.getId());
    }

    private String extractResult(Event event, Position position) {
        Object value = event.getAttributes() != null
                ? event.getAttributes().get(Position.KEY_RESULT) : null;
        if (value == null && position != null && position.getAttributes() != null) {
            value = position.getAttributes().get(Position.KEY_RESULT);
        }
        return value == null ? "" : value.toString().trim();
    }

    private static boolean isSuccess(String result) {
        String normalized = result.trim().toLowerCase();
        return normalized.equals("success")
                || normalized.equals("ok")
                || normalized.equals("done")
                || normalized.equals("true");
    }

    private boolean isInboxEvent(String type) {
        if (type == null || type.isBlank()) {
            return false;
        }
        String configured = config.getString("notificator.webhook.inboxTypes");
        if (configured == null || configured.isBlank()) {
            configured = Event.TYPE_COMMAND_RESULT;
        }
        for (String item : configured.split(",")) {
            if (item.trim().equalsIgnoreCase(type)) {
                return true;
            }
        }
        return false;
    }

    /**
     * 收件箱地址：优先读 `notificator.webhook.inboxUrl`；
     * 否则把事件地址的 `/v1/events` 替换为 `/v1/messages`。
     */
    private String resolveInboxUrl(String eventUrl) {
        String explicit = config.getString("notificator.webhook.inboxUrl");
        if (explicit != null && !explicit.isBlank()) {
            return explicit.trim();
        }
        int index = eventUrl.lastIndexOf("/v1/events");
        if (index < 0) {
            return null;
        }
        return eventUrl.substring(0, index) + "/v1/messages";
    }

    private CompletableFuture<Void> post(
            String url, String body, long timeoutSeconds, long eventId, long userId) throws Exception {

        HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(timeoutSeconds))
                .header("Content-Type", "application/json; charset=utf-8")
                .header("User-Agent", "traccar-webhook/1")
                .POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8));

        String secret = config.getString("notificator.webhook.secret");
        if (secret != null && !secret.isBlank()) {
            builder.header("X-Traccar-Signature", "sha256=" + hmacSha256(body, secret));
        }

        return httpClient.sendAsync(builder.build(), HttpResponse.BodyHandlers.ofString())
                .thenAccept(response -> {
                    if (response.statusCode() / 100 != 2) {
                        LOGGER.warn(
                                "Webhook rejected event {} for user {}: HTTP {} {}",
                                eventId, userId,
                                response.statusCode(), response.body());
                        throw new CompletionException(new IllegalStateException(
                                "Webhook returned HTTP " + response.statusCode()));
                    }
                });
    }

    private static long parseLong(String value, long fallback) {
        if (value == null || value.isBlank()) {
            return fallback;
        }
        try {
            return Long.parseLong(value.trim());
        } catch (NumberFormatException error) {
            return fallback;
        }
    }

    private static String hmacSha256(String body, String secret) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        byte[] digest = mac.doFinal(body.getBytes(StandardCharsets.UTF_8));
        StringBuilder builder = new StringBuilder(digest.length * 2);
        for (byte value : digest) {
            builder.append(String.format("%02x", value));
        }
        return builder.toString();
    }
}
