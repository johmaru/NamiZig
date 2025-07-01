#if defined(_M_X64) && !defined(_M_AMD64)
#define _M_AMD64 _M_X64
#endif
#if defined(_M_AMD64) && !defined(_AMD64_)
#define _AMD64_
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <cwchar>
#include <cstddef>

#ifdef __cplusplus
#include <commctrl.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <Uxtheme.h>
#include <ole2.h>
#include <oleauto.h>
#include <combaseapi.h>
#include <wrl/client.h>
#include <wrl/event.h>
#else
  #include <stddef.h>
  #include <stdint.h>
  typedef void *HWND;
  typedef long HRESULT;
  typedef unsigned long ULONG;
  #define S_OK       ((HRESULT)0L)
  #define E_POINTER  ((HRESULT)0x80004003L)
  #ifndef E_FAIL
  #define E_FAIL ((HRESULT)0x80004005L)
  #endif
#endif

#include <WebView2EnvironmentOptions.h>
#include <WebView2.h>

#pragma comment(lib, "shlwapi.lib")

#define WEBVIEW_WRAPPER_EXPORTS
#include "webview_wrapper_c.h"


#ifdef __cplusplus
using namespace Microsoft::WRL;
#endif


extern "C" {
    HRESULT create_webview_environment(void** environment);
    HRESULT create_webview_controller(void* environment, HWND hwnd, void** controller, controllerSettings settings);
    HRESULT navigate_webview(void* controller_in, const char* url_utf8);
    void resize_webview(void* controller_in, RECT bounds);
    void cleanup_webview(void* controller, void* environment);
    HRESULT register_web_message_handler(void* controller, WebMessageReceivedCallback callback);
    HRESULT execute_script(void* controller, const char* script);

    HRESULT __stdcall wrapper_SetWindowTheme(HWND hwnd, const wchar_t *pszSubAppName, const wchar_t *pszSubIdList);

    const unsigned int WRAPPER_TBN_DROPDOWN = TBN_DROPDOWN;
    const unsigned int WRAPPER_NM_CUSTOMDRAW = NM_CUSTOMDRAW;
}

static EventRegistrationToken webMessageToken = {};
static WebMessageReceivedCallback g_webMessageCallback = nullptr;

HRESULT register_web_message_handler(void* controller_in, WebMessageReceivedCallback callback) {
    if (controller_in == nullptr || callback == nullptr) {
        return E_POINTER;
    }

#ifdef __cplusplus
    g_webMessageCallback = callback;
    ICoreWebView2Controller* controller = static_cast<ICoreWebView2Controller*>(controller_in);
    ComPtr<ICoreWebView2> webview;
    HRESULT hr = controller->get_CoreWebView2(&webview);

    if (SUCCEEDED(hr) && webview != nullptr) {
        hr = webview->add_WebMessageReceived(
            Microsoft::WRL::Callback<ICoreWebView2WebMessageReceivedEventHandler>(
                [](ICoreWebView2* sender, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
                    if (g_webMessageCallback == nullptr) {
                        return E_FAIL;
                    }

                    LPWSTR message;
                    HRESULT hr = args->get_WebMessageAsJson(&message);
                    if (SUCCEEDED(hr)) {
                        if (message == nullptr) {
                            g_webMessageCallback("");
                            return S_OK;
                        }

                        int utf8_length = WideCharToMultiByte(CP_UTF8, 0, message, -1, NULL, 0, NULL, NULL);
                        if (utf8_length > 0) {
                            std::vector<char> utf8_buffer(utf8_length);
                            WideCharToMultiByte(CP_UTF8, 0, message, -1, utf8_buffer.data(), utf8_length, NULL, NULL);
                            g_webMessageCallback(utf8_buffer.data());
                        } else {
                            g_webMessageCallback("");
                        }
                        CoTaskMemFree(message);
                    }
                    return S_OK;
                }
            ).Get(),
            &webMessageToken
        );
    }
    return hr;
#else
    return E_NOTIMPL;
#endif
}

HRESULT execute_script(void* controller_in, const char* script) {
    if (controller_in == nullptr || script == nullptr) {
        return E_POINTER;
    }

    #ifdef __cplusplus
        ICoreWebView2Controller* controller = static_cast<ICoreWebView2Controller*>(controller_in);
        ComPtr<ICoreWebView2> webview;
        HRESULT hr = controller->get_CoreWebView2(&webview);

        if (SUCCEEDED(hr) && webview != nullptr) {
            int wide_char_len = MultiByteToWideChar(CP_UTF8, 0, script, -1, NULL, 0);

            if (wide_char_len <= 0) {
                return HRESULT_FROM_WIN32(GetLastError());
            }
            wchar_t* wide_script = new (std::nothrow) wchar_t[wide_char_len];
            if (wide_script == nullptr) {
                return E_OUTOFMEMORY;
            }

            if (MultiByteToWideChar(CP_UTF8, 0, script, -1, wide_script, wide_char_len) == 0) {
                delete[] wide_script;
                return HRESULT_FROM_WIN32(GetLastError());
            }

            hr = webview->ExecuteScript(wide_script, nullptr);
            delete[] wide_script;
        } else if (SUCCEEDED(hr) && webview == nullptr) {
            return E_FAIL;
        }
        return hr;
    #else
        return E_NOTIMPL;
    #endif
        }

#pragma comment(lib, "uxtheme.lib")
HRESULT __stdcall wrapper_SetWindowTheme(HWND hwnd, const wchar_t *pszSubAppName, const wchar_t *pszSubIdList) {
    if (hwnd == nullptr) return E_POINTER;
    return SetWindowTheme(hwnd, pszSubAppName, pszSubIdList);
}

HRESULT create_webview_environment(void** environment) {
    if (environment == nullptr) {
        return E_POINTER;
    }
    
    *environment = nullptr;

    #ifdef __cplusplus
        HANDLE hEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
    if (hEvent == NULL) {
        return HRESULT_FROM_WIN32(GetLastError());
    }

    HRESULT callback_hr = E_FAIL;
    HRESULT final_hr = E_FAIL;

    HRESULT hr_async_start = CreateCoreWebView2EnvironmentWithOptions(
        nullptr, // browserExecutableFolder
        nullptr, // userDataFolder
        nullptr, // environmentOptions
        Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [environment,hEvent,&callback_hr](HRESULT result, ICoreWebView2Environment* env) -> HRESULT {
                char buffer[256];
                sprintf_s(buffer, sizeof(buffer), "  Callback Result HRESULT: 0x%lX\n", result);
                OutputDebugStringA(buffer);

                callback_hr = result;
                if (SUCCEEDED(result) && env != nullptr) {
                    *environment = env;
                    env->AddRef();

                } else {
                    *environment = nullptr;
                    if (FAILED(result)) {
                        sprintf_s(buffer, sizeof(buffer), "  Callback FAILED. HRESULT: 0x%lX. *controller_out set to NULL.\n", result);
                        OutputDebugStringA(buffer);
                    } else { 
                         OutputDebugStringA("  Callback SUCCEEDED but ctrl is NULL. *controller_out set to NULL.\n");
                    }
                }
                SetEvent(hEvent);
                return result;
            }
        ).Get()
    );

    final_hr = callback_hr;
    if (SUCCEEDED(hr_async_start)) {
        DWORD wait_result;
        for (;;) {
            wait_result = MsgWaitForMultipleObjects(1, &hEvent, FALSE, 30000, QS_ALLINPUT);

            if (wait_result == WAIT_OBJECT_0) {
                final_hr = callback_hr;
                break;
            }

            if (wait_result == WAIT_FAILED
                || wait_result == WAIT_TIMEOUT) {
                final_hr = (wait_result == WAIT_TIMEOUT) ? HRESULT_FROM_WIN32(ERROR_TIMEOUT) : E_FAIL;
                OutputDebugStringA("create_webview_environment: MsgWaitForMultipleObjects timed out or failed.\n");
                if (*environment != nullptr) {
                    static_cast<ICoreWebView2Environment*>(*environment)->Release();
                    *environment = nullptr;
                }
                break;
            }

            MSG msg;
            while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
                TranslateMessage(&msg);
                DispatchMessage(&msg);
            }
        }
    } else {
        final_hr = hr_async_start;
        *environment = nullptr;
        OutputDebugStringA("CreateCoreWebView2EnvironmentWithOptions (async start) failed.\n");
    }
    CloseHandle(hEvent);

    if (FAILED(final_hr) && *environment != nullptr) {
        OutputDebugStringA("create_webview_environment: final_hr indicates failure, but *environment was set. Cleaning up.\n");
        static_cast<ICoreWebView2Environment*>(*environment)->Release();
        *environment = nullptr;
    }

    char final_buffer[256];
    sprintf_s(final_buffer, sizeof(final_buffer), "create_webview_environment returning: 0x%lX, *environment: %p\n", final_hr, *environment);
    OutputDebugStringA(final_buffer);
    return final_hr;
    #else
    return E_NOTIMPL;
    #endif
}

HRESULT create_webview_controller(void* environment, HWND hwnd, void** controller, controllerSettings settings) {
    if (controller == nullptr || environment == nullptr || hwnd == nullptr) {
        return E_POINTER;
    }

    *controller = nullptr;

#ifdef __cplusplus
    ICoreWebView2Environment* env = static_cast<ICoreWebView2Environment*>(environment);
    HANDLE hEvent = CreateEvent(NULL, FALSE, FALSE, NULL);
    if (hEvent == NULL) {
        return HRESULT_FROM_WIN32(GetLastError());
    }
    
    HRESULT callback_hr = E_FAIL;
    HRESULT final_hr = E_FAIL;
    HRESULT hr_async_start = env->CreateCoreWebView2Controller(
        hwnd,
        Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
            [controller, hwnd, hEvent, &callback_hr, settings, env](HRESULT result, ICoreWebView2Controller* ctrl) -> HRESULT {
                OutputDebugStringA("CreateCoreWebView2Controller COMPLETED HANDLER called.\n");
                char buffer[256];
                sprintf_s(buffer, sizeof(buffer), "  Callback Result HRESULT: 0x%lX\n", result);
                OutputDebugStringA(buffer);

                callback_hr = result;

                if (SUCCEEDED(result) && ctrl != nullptr) {
                    *controller = ctrl;
                    ctrl->AddRef();

                    ComPtr<ICoreWebView2> webview;
                    HRESULT hr = ctrl->get_CoreWebView2(&webview);

                    if (SUCCEEDED(hr) && webview != nullptr) {
                        ComPtr<ICoreWebView2Settings> webview_settings;
                        HRESULT hr_settings = webview->get_Settings(&webview_settings);
                        if (SUCCEEDED(hr_settings) && webview_settings != nullptr) {
                            webview_settings->put_AreDefaultContextMenusEnabled(settings.contextMenu);
                        }

                        if (settings.isVirtualHost) {
                            webview->AddWebResourceRequestedFilter(L"https://assets.namizig.com/*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);

                            EventRegistrationToken token;
                            webview->add_WebResourceRequested(
                                Microsoft::WRL::Callback<ICoreWebView2WebResourceRequestedEventHandler>(
                                    [settings, env](ICoreWebView2* sender, ICoreWebView2WebResourceRequestedEventArgs* args) -> HRESULT {
                                        ComPtr<ICoreWebView2WebResourceRequest> request;
                                        args->get_Request(&request);
                                        LPWSTR uri_w;
                                        request->get_Uri(&uri_w);
                                        std::wstring uri(uri_w);
                                        CoTaskMemFree(uri_w);

                                        if (uri == L"https://assets.namizig.com/main.html") {
                                            std::string htmlTemplate;
                                            if (settings.htmlContent != nullptr && settings.htmlContent[0] != '\0') {
                                                htmlTemplate = settings.htmlContent;
                                            } else {
                                                wchar_t exePath[MAX_PATH];
                                                GetModuleFileNameW(NULL, exePath, MAX_PATH);
                                                PathRemoveFileSpecW(exePath);
                                                std::wstring htmlFilePath = std::wstring(exePath) + L"\\testvirtualhost\\main.html";

                                                std::ifstream htmlFile(htmlFilePath, std::ios::binary);
                                                if (htmlFile.is_open()) {
                                                    std::stringstream ss;
                                                    ss << htmlFile.rdbuf();
                                                    htmlTemplate = ss.str();
                                                    htmlFile.close();
                                                }
                                        
                                            }
                                            
                                            std::string htmlContent = htmlTemplate;

                                            const std::string start_tag = "<template ";
                                            const std::string end_tag = "></template>";
                                            size_t search_pos = 0;
                                            size_t start_pos;
                                            while ((start_pos = htmlContent.find(start_tag, search_pos)) != std::string::npos) {
                                                size_t end_pos = htmlContent.find(end_tag, start_pos);
                                                if (end_pos == std::string::npos) {

                                                    search_pos = start_pos + start_tag.length();
                                                    continue;
                                                }

                                                size_t content_start = start_pos + start_tag.length();
                                                std::string content = htmlContent.substr(content_start, end_pos - content_start);

                                                size_t first_comma = content.find(',');
                                                size_t second_comma = content.find(',', first_comma + 1);
                                                
                                                if (first_comma != std::string::npos && second_comma != std::string::npos) {
                                                    std::string event_type = content.substr(0, first_comma);
                                                    std::string event_key = content.substr(first_comma + 1, second_comma - (first_comma + 1));

                                                    std::string element_id;
                                                    std::string payload_content;

                                                    size_t third_comma = content.find(',', second_comma + 1);
                                                    if (third_comma != std::string::npos) {
                                                        element_id = content.substr(second_comma + 1, third_comma - (second_comma + 1));
                                                        payload_content = content.substr(third_comma + 1);
                                                    } else {
                                                        element_id = content.substr(second_comma + 1);
                                                    }

                                                    auto trim = [](std::string& s, const char* t = " \t\n\r\f\v") {
                                                        s.erase(0, s.find_first_not_of(t));
                                                        s.erase(s.find_last_not_of(t) + 1);
                                                    };
                                                    trim(event_type, " \t\n\r\f\v");
                                                    trim(event_key, " \t\n\r\f\v");
                                                    trim(element_id);
                                                    trim(payload_content, " \t\n\r\f\v");

                                                    if (!event_type.empty() && !element_id.empty()) {
                                                        if (event_type == "click") {
                                                            std::string js_script = "<script>";
                                                            js_script += "document.getElementById(" + element_id + ").addEventListener('" + event_type + "', () => {";
                                                            std::string message_object = "{ command: 'buttonClick', event_key: '" + event_key + "'";
                                                            if (!payload_content.empty()) {
                                                                message_object += ", payload: { " + payload_content + " }";
                                                            }
                                                            message_object += " }";

                                                            js_script += "  const message = " + message_object + ";";
                                                            js_script += "  window.chrome.webview.postMessage(message);";
                                                            js_script += "  console.log('Message sent:', message);";
                                                            js_script += "});";
                                                            js_script += "</script>";

                                                            htmlContent.replace(start_pos, (end_pos + end_tag.length()) - start_pos, js_script);
                                                            
                                                            search_pos = start_pos + js_script.length();
                                                            continue; 
                                                        }
                                                    }
                                                }
                                                // パースに失敗した場合、このタグをスキップして次に進む
                                                search_pos = start_pos + start_tag.length();
                                            }

                                            ComPtr<IStream> stream = SHCreateMemStream(
                                                reinterpret_cast<const BYTE*>(htmlContent.c_str()),
                                                static_cast<UINT>(htmlContent.length())
                                            );

                                            if (stream) {
                                                ComPtr<ICoreWebView2WebResourceResponse> response;
                                                env->CreateWebResourceResponse(
                                                    stream.Get(), 200, L"OK", L"Content-Type: text/html; charset=utf-8", &response
                                                );
                                                args->put_Response(response.Get());
                                            }
                                        }
                                        return S_OK;
                                    }
                                ).Get(), &token
                            );
                        }
                    }
                } else {
                    *controller = nullptr;
                }
                SetEvent(hEvent);
                return result;
            }
        ).Get()
    );


    final_hr = callback_hr;
    if (SUCCEEDED(hr_async_start)) {
        

   DWORD wait_result;
   for (;;) {
    wait_result = MsgWaitForMultipleObjects(1, &hEvent, FALSE, 30000, QS_ALLINPUT);
                        
    if (wait_result == WAIT_OBJECT_0) {
        final_hr = callback_hr;
        break;
    }
                        
    if (wait_result == WAIT_FAILED
        || wait_result == WAIT_TIMEOUT) {
        final_hr = (wait_result == WAIT_TIMEOUT) ? HRESULT_FROM_WIN32(ERROR_TIMEOUT) : E_FAIL;
        OutputDebugStringA("create_webview_controller: MsgWaitForMultipleObjects timed out or failed.\n");
        if (*controller != nullptr) {
            static_cast<ICoreWebView2Controller*>(*controller)->Close();
            static_cast<ICoreWebView2Controller*>(*controller)->Release();
            *controller = nullptr;
        }
            break;
        }
                        
        MSG msg;
        while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        }                     
    } else {
        final_hr = hr_async_start;
        *controller = nullptr;
        OutputDebugStringA("CreateCoreWebView2Controller (async start) failed.\n");
    }
    CloseHandle(hEvent);

    if (FAILED(final_hr) && *controller != nullptr) {
        static_cast<ICoreWebView2Controller*>(*controller)->Close();
        static_cast<ICoreWebView2Controller*>(*controller)->Release();
        *controller = nullptr;
    }

    char final_buffer[256];
    sprintf_s(final_buffer, sizeof(final_buffer), "create_webview_controller returning: 0x%lX, *controller_out: %p\n", final_hr, *controller);
    OutputDebugStringA(final_buffer);

    return final_hr;
#else
    return E_NOTIMPL;
#endif
}

HRESULT navigate_webview(void* controller_in, const char* url_utf8) {
    if (controller_in == nullptr || url_utf8 == nullptr) {
        return E_POINTER;
    }

    #ifdef __cplusplus
    ICoreWebView2Controller* controller = static_cast<ICoreWebView2Controller*>(controller_in);
    ComPtr<ICoreWebView2> webview;
    HRESULT hr = controller->get_CoreWebView2(&webview);
    if (SUCCEEDED(hr) && webview != nullptr) {
        int wide_char_len = MultiByteToWideChar(CP_UTF8, 0, url_utf8, -1, NULL, 0);
        if (wide_char_len <= 0) {
            return HRESULT_FROM_WIN32(GetLastError());
        }
        wchar_t* wide_url = new (std::nothrow) wchar_t[wide_char_len];
        if (wide_url == nullptr) {
            return E_OUTOFMEMORY;
        }

        if (MultiByteToWideChar(CP_UTF8, 0, url_utf8, -1, wide_url, wide_char_len) == 0) {
            delete[] wide_url;
            return HRESULT_FROM_WIN32(GetLastError());
        }

        hr = webview->Navigate(wide_url);
        delete[] wide_url;
    } else if (SUCCEEDED(hr) && webview == nullptr) {
        return E_FAIL;
    }
    return hr;
    #else
    return E_NOTIMPL;
    #endif
}

void resize_webview(void* controller_in, RECT bounds) {
#ifdef __cplusplus
    if (controller_in != nullptr) {
        ICoreWebView2Controller* controller = static_cast<ICoreWebView2Controller*>(controller_in);
        controller->put_Bounds(bounds);
    }
#endif
}

void cleanup_webview(void* controller, void* environment) {
    #ifdef __cplusplus
    if (controller != nullptr) {
        ICoreWebView2Controller* ctrl = static_cast<ICoreWebView2Controller*>(controller);
        ctrl->Close();
        ctrl->Release();
    }
    if (environment != nullptr) {
        ICoreWebView2Environment* env = static_cast<ICoreWebView2Environment*>(environment);
        env->Release();
    }
    #endif
}