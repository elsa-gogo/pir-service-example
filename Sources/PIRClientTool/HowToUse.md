# How to use

`swift run PIRClientTool --base-url http://localhost:8080 --usecase <pir_usecase> --phone-number +886987654321`

## Supported Params

* `--base-url <base-url>`：PIR Service URL (例如: https://example.com 或 http://localhost:8080)
* `--phone-number <phone-number>`：要查詢的電話號碼，需用 e164 格式 (例如: +886987654321)
* `--usecase <usecase>`：要查詢的 PIR Usecase（default: test）
* `--symmetric`：(optional) 使用對稱 PIR 查詢 (default: false)
* `--user-token <user-token>`：(optional)For Privacy Pass Authentication
* `--platform <platform>`：(optional) 平台類型，可支援的值：`iOS18`, `iOS18_2`, `macOS15`, `macOS15_2`，預設: `iOS18`
* `-h`, `--help`
