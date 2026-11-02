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
 * &lt;entry key='notificator.webhook.secret'&gt;请替换为随机密钥&lt;/entry&gt;
 * &lt;entry key='notificator.webhook.timeoutSeconds'&gt;5&lt;/entry&gt;
 * </pre>
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

            long timeoutSeconds = parseLong(
                    config.getString("notificator.webhook.timeoutSeconds"), 5L);
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
                                    event.getId(), user.getId(),
                                    response.statusCode(), response.body());
                            throw new CompletionException(new IllegalStateException(
                                    "Webhook returned HTTP " + response.statusCode()));
                        }
                    });

        } catch (Exception error) {
            LOGGER.warn("Webhook delivery failed for event {}", event.getId(), error);
            return CompletableFuture.failedFuture(error);
        }
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
