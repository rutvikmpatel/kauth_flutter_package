## 0.0.5

* Fix iOS background resume 401 burst with proactive JWT expiration checks.
* Add clock skew and network transit window safety buffer (30s) to preventative refresh.
* Resolve `QueuedInterceptorsWrapper` re-entrant deadlock on 401 retries using isolated `_retryDio`.
* Add single-flight Future memoization to deduplicate concurrent token refreshes across multiple Dio instances.
* Guard against `FormData` stream exhaustion during retry attempts.
* Ensure offline sessions are never cleared on cold boot by managing token lifetime via JWT payload.
* Pass `providerId` during `setSession` to ensure `AuthManager.refreshSession` reliably resolves the provider.
* Whitelist explicit Keycloak revocation error codes (`invalid_grant`, `invalid_token`, session not found) to prevent false-positive logouts from rate limits (429) or transient network drops.

## 0.0.1

* Initial release.
* Features: OTP Login, Token Refresh, Secure Storage, Custom Configuration, Error Handling.
