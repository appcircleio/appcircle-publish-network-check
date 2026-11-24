# Appcircle Publish Check Network Access Components

Check whether the runner can reach the app store endpoints used by the Appcircle publish module. The components run on the runner during a publish flow, so they show what the runner's network, proxy and trust store actually allow.

One script (`main.rb`) backs both components:

- `appcircle_publish_check_network_access_ios`: App Store endpoints.
- `appcircle_publish_check_network_access_android`: Google Play and Huawei AppGallery endpoints.

The mirrors of the registry files are `component-ios.yaml` and `component-android.yaml`.

## Result rules

- Reachable: any HTTP response, including 3xx, 401, 403, 404 and 5xx. Redirects are not followed.
- Not reachable: DNS, TCP, TLS or proxy errors, a timeout, a proxy that refused the CONNECT request (status other than 200), or HTTP 407.
- HTTP 403 counts as reachable, but it may come from a proxy. Check the `Server` header printed for the endpoint.

For every endpoint that is not reachable, the log shows the `curl -v` trace of the same attempt, the meaning of the curl exit code and a local DNS lookup of the host. Proxy credentials and `Authorization` / `Proxy-Authorization` values are masked.

## iOS inputs

- `AC_CHECK_NETWORK_API_APPSTORECONNECT_APPLE_COM`: Checks `https://api.appstoreconnect.apple.com/`. Default: `true`.
- `AC_CHECK_NETWORK_APPSTORECONNECT_APPLE_COM`: Checks `https://appstoreconnect.apple.com/`. Default: `true`.
- `AC_CHECK_NETWORK_CONTENTDELIVERY_ITUNES_APPLE_COM`: Checks `https://contentdelivery.itunes.apple.com/`. Default: `true`.
- `AC_CHECK_NETWORK_NORTHAMERICA_1_OBJECT_STORAGE_APPLE_COM`: Checks `https://northamerica-1.object-storage.apple.com/`. Default: `true`.
- `AC_CHECK_NETWORK_API_ENTERPRISE_DEVELOPER_APPLE_COM`: Checks `https://api.enterprise.developer.apple.com/`. Enable it only when using an Apple Enterprise API key. Default: `false`.

## Android inputs

- `AC_CHECK_NETWORK_WWW_GOOGLEAPIS_COM`: Checks `https://www.googleapis.com/`. Default: `true`.
- `AC_CHECK_NETWORK_ANDROIDPUBLISHER_GOOGLEAPIS_COM`: Checks `https://androidpublisher.googleapis.com/`. Default: `true`.
- `AC_CHECK_NETWORK_CONNECT_API_CLOUD_HUAWEI_COM`: Checks `https://connect-api.cloud.huawei.com/`. Default: `true`.

Huawei AppGallery uploads go to a dynamic host (for example `nsp-appgallery-agcfs-dre.obs.eu-de.otc.t-systems.com`) that depends on the account and region and is returned by an authenticated API call. It is not checked. When the Huawei input is `true`, the log shows a warning and the summary lists the host as `NOT CHECKED`. If you know the host, add it to `AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS`.

## Shared inputs

- `AC_CHECK_CONNECTION_TIMEOUT`: Maximum time (integer, in seconds) allowed for establishing a connection. Default: `8`.
- `AC_CHECK_CONNECTION_MAX_TIMEOUT`: Maximum total time (integer, in seconds) allowed for one request. Default: `20`. It must not be smaller than the connection timeout.
- `AC_CHECK_NETWORK_EXTRA_URL_PARAMETERS`: Additional URLs to check, as a comma separated list (e.g. `https://url1.com, https://url2.com`).

## Output and exit behavior

The log starts with the curl version and the runner's proxy and CA environment variables (credentials masked), then lists each endpoint with its result, HTTP status and time. The summary table has the columns Endpoint, Result (`REACHABLE`, `NOT REACHABLE`, `NOT CHECKED`) and Reason.

All endpoints are checked before the script ends. It exits `1` with an `@@[error]` line if any selected endpoint is not reachable, and `0` otherwise, or when no endpoint is selected.

## Proxy and certificates

The script does not set a proxy or disable certificate checks. curl uses the runner's `HTTPS_PROXY`, `HTTP_PROXY`, `ALL_PROXY` and `NO_PROXY` variables and its own trust store (or `SSL_CERT_FILE` / `CURL_CA_BUNDLE` when set).

## Tests

```
for f in test/*_test.rb; do ruby "$f"; done
bash test/integration.sh
```

`test/integration.sh` runs `main.rb` against the real endpoints, directly and behind a local proxy that blocks one host (`test/blocking_proxy.rb`). It needs internet access. Output goes to `test/output/`.
