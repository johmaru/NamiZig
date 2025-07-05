#include <intsafe.h>
#define WIN32_LEAN_AND_MEAN

#include <windows.h>

#if defined(_M_X64) && !defined(_M_AMD64)
#define _M_AMD64 _M_X64
#endif
#if defined(_M_AMD64) && !defined(_AMD64_)
#define _AMD64_
#endif

#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <cstddef>

#include <commctrl.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <Uxtheme.h>
#include <wrl/client.h>
#include <wrl/event.h>

#include <WebView2EnvironmentOptions.h>
#include <WebView2.h>

#pragma comment(lib, "shlwapi.lib")

#define WEBVIEW_WRAPPER_EXPORTS
#include "webview_wrapper_c.h"

using namespace Microsoft::WRL;


extern "C" {
    HRESULT create_webview_environment(void** environment);
    HRESULT create_webview_controller_async(void* environment, HWND_HANDLE hwnd, const controllerSettings* settings, WebViewCreatedCallback on_completed, void* context);
    HRESULT navigate_webview(void* controller_in, const char* url_utf8);
    void resize_webview(void* controller_in, RECT bounds);
    void    cleanup_webview(void* controller, void* environment);
    HRESULT register_web_message_handler(void* controller_in, WebMessageReceivedCallback callback);
    HRESULT execute_script(void* controller, const char* script);
    HRESULT __stdcall wrapper_SetWindowTheme(HWND_HANDLE hwnd, const wchar_t *pszSubAppName, const wchar_t *pszSubIdList);
    HRESULT setup_accelerator_handler(void* controller);

    const unsigned int WRAPPER_TBN_DROPDOWN = TBN_DROPDOWN;
    const unsigned int WRAPPER_NM_CUSTOMDRAW = NM_CUSTOMDRAW;
}

static EventRegistrationToken webMessageToken = {};
static EventRegistrationToken acceleratorToken = {};

static WebMessageReceivedCallback g_webMessageCallback = nullptr;


HRESULT register_web_message_handler(void* controller_in, WebMessageReceivedCallback callback) {
    if (controller_in == nullptr || callback == nullptr) {
        return E_POINTER;
    }
    OutputDebugStringA("C++: register_web_message_handler entered.\n");

    g_webMessageCallback = callback;
    ICoreWebView2Controller* controller = static_cast<ICoreWebView2Controller*>(controller_in);
    
    ComPtr<ICoreWebView2> webview;
    HRESULT hr = controller->get_CoreWebView2(&webview);
    if (FAILED(hr) || webview == nullptr) {
        OutputDebugStringA("C++: register_web_message_handler failed to get CoreWebView2.\n");
        return FAILED(hr) ? hr : E_FAIL;
    }

    HWND hwnd = nullptr;
    HRESULT hr_hwnd = controller->get_ParentWindow(&hwnd);
    if (FAILED(hr_hwnd)) {
        OutputDebugStringA("C++: register_web_message_handler failed to get ParentWindow.\n");
        return hr_hwnd;
    }

    OutputDebugStringA("C++: About to add WebMessageReceived handler.\n");
    hr = webview->add_WebMessageReceived(
        Microsoft::WRL::Callback<ICoreWebView2WebMessageReceivedEventHandler>(
            [hwnd](ICoreWebView2* sender, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
                OutputDebugStringA("C++: WebMessageReceived lambda entered.\n");
                if (g_webMessageCallback == nullptr) {
                    OutputDebugStringA("C++: g_webMessageCallback is null in lambda. Aborting.\n");
                    return E_FAIL;
                }

                LPWSTR message_ws = nullptr;
                HRESULT hr_json = args->get_WebMessageAsJson(&message_ws);
                if (FAILED(hr_json)) {
                    OutputDebugStringA("C++: get_WebMessageAsJson failed.\n");
                    return S_OK;
                }
                
                struct CoTaskMemFreer {
                    LPWSTR& p;
                    ~CoTaskMemFreer() { if (p) CoTaskMemFree(p); }
                } freer = { message_ws };

                const char* utf8_message_to_pass = nullptr;
                if (message_ws != nullptr && *message_ws != L'\0') {
                    int utf8_length = WideCharToMultiByte(CP_UTF8, 0, message_ws, -1, NULL, 0, NULL, NULL);
                    if (utf8_length > 0) {

                        char* utf8_buffer = static_cast<char*>(CoTaskMemAlloc(utf8_length));
                        if (utf8_buffer != nullptr) {
                            WideCharToMultiByte(CP_UTF8, 0, message_ws, -1, utf8_buffer, utf8_length, NULL, NULL);
                            utf8_message_to_pass = utf8_buffer;
                            }
                        }
                    }

                char debug_buffer[256];
                sprintf_s(debug_buffer, "C++: About to call Zig callback g_webMessageCallback with HWND=%p, message_ptr=%p\n", hwnd, utf8_message_to_pass);
                OutputDebugStringA(debug_buffer);

                g_webMessageCallback(static_cast<HWND_HANDLE>(hwnd), utf8_message_to_pass);

                OutputDebugStringA("C++: Zig callback g_webMessageCallback returned.\n");
                return S_OK;
            }
        ).Get(),
        &webMessageToken
    );
    
    return hr;
}

HRESULT setup_accelerator_handler(void* controller_in) {
    if (controller_in == nullptr) {
        return E_POINTER;
    }
    ICoreWebView2Controller* c = (ICoreWebView2Controller*)controller_in;
    return c->add_AcceleratorKeyPressed(
        Callback<ICoreWebView2AcceleratorKeyPressedEventHandler>(
            [](ICoreWebView2Controller* sender, ICoreWebView2AcceleratorKeyPressedEventArgs* args) -> HRESULT {
                return S_OK;
            }).Get(), &acceleratorToken);
}

HRESULT execute_script(void* controller_in, const char* script) {
    if (controller_in == nullptr || script == nullptr) {
        return E_POINTER;
    }

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
}

static std::wstring Utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) {
        return std::wstring();
    }
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &utf8[0], (int)utf8.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &utf8[0], (int)utf8.size(), &wstrTo[0], size_needed);
    return wstrTo;
}

static std::wstring Utf8ToWide(const char* utf8_c_str) {
    if (utf8_c_str == nullptr || *utf8_c_str == '\0') {
        return std::wstring();
    }
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, utf8_c_str, -1, NULL, 0);
    if (size_needed <= 0) {
        return std::wstring();
    }
    std::vector<wchar_t> buffer(size_needed);
    MultiByteToWideChar(CP_UTF8, 0, utf8_c_str, -1, buffer.data(), size_needed);
    std::wstring wstrTo(buffer.data());
    return wstrTo;
}

#pragma comment(lib, "uxtheme.lib")
HRESULT __stdcall wrapper_SetWindowTheme(HWND_HANDLE hwnd_in, const wchar_t *pszSubAppName, const wchar_t *pszSubIdList) {
    HWND hwnd = static_cast<HWND>(hwnd_in);
    return SetWindowTheme(hwnd, pszSubAppName, pszSubIdList);
}

HRESULT create_webview_environment(void** environment) {
    if (environment == nullptr) {
        return E_POINTER;
    }
    
    *environment = nullptr;

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
}

HRESULT create_webview_controller_async(void* environment, HWND_HANDLE hwnd_in, const controllerSettings* settings, WebViewCreatedCallback on_completed, void* context) {
    if (environment == nullptr || hwnd_in == nullptr || settings == nullptr || on_completed == nullptr) {
        return E_POINTER;
    }
    
    HWND hwnd = static_cast<HWND>(hwnd_in);

    ICoreWebView2Environment* env = static_cast<ICoreWebView2Environment*>(environment);
   
    HRESULT hr_async_start = env->CreateCoreWebView2Controller(
        hwnd,
        Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(

            [on_completed, context, saved_settings = *settings](HRESULT result, ICoreWebView2Controller* ctrl) -> HRESULT {
                OutputDebugStringA("CreateCoreWebView2Controller COMPLETED HANDLER called.\n");

                if (FAILED(result) || ctrl == nullptr) {
                    on_completed(result, nullptr, context);
                    return result;
                }

                ctrl->AddRef();
                ctrl->put_IsVisible(TRUE);

                ComPtr<ICoreWebView2> webview;
                HRESULT hr = ctrl->get_CoreWebView2(&webview);

                if (FAILED(hr) || webview == nullptr) {
                    ctrl->Release();
                    on_completed(hr, nullptr, context);
                    return hr;
                }

                ComPtr<ICoreWebView2Settings> webview_settings;
                webview->get_Settings(&webview_settings);
                if (webview_settings != nullptr) {
                    webview_settings->put_AreDefaultContextMenusEnabled(saved_settings.contextMenu);
                }

                if (saved_settings.isVirtualHost && saved_settings.virtualHostName != nullptr && saved_settings.htmlContent != nullptr) {
                    ComPtr<ICoreWebView2_3> webview3;
                    if (SUCCEEDED(webview.As(&webview3))) {
                        std::wstring host_name_w = Utf8ToWide(saved_settings.virtualHostName);
                        std::wstring folder_path_w = Utf8ToWide(saved_settings.htmlContent);
                        OutputDebugStringW((L"SetVirtualHostNameToFolderMapping called with:\n  Host Name: " + host_name_w + L"\n  Folder Path: " + folder_path_w + L"\n").c_str());
                        webview3->SetVirtualHostNameToFolderMapping(host_name_w.c_str(), folder_path_w.c_str(), COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
                    } else {
                        OutputDebugStringA("ICoreWebView2_3 interface not available. Virtual host mapping skipped.\n");
                    }
                }

                on_completed(result, ctrl, context);
                return result;
            }
        ).Get()
    );

    if (FAILED(hr_async_start)) {
        OutputDebugStringA("CreateCoreWebView2Controller (async start) failed.\n");
    }
    
    return hr_async_start;
}

HRESULT navigate_webview(void* controller_in, const char* url_utf8) {
    if (controller_in == nullptr || url_utf8 == nullptr) {
        return E_POINTER;
    }

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
}

void resize_webview(void* controller_in, RECT bounds) {
    if (controller_in != nullptr) {
        ICoreWebView2Controller* controller = static_cast<ICoreWebView2Controller*>(controller_in);
        controller->put_Bounds(bounds);
    }
}

void cleanup_webview(void* controller, void* environment) {
    if (controller != nullptr) {
        ICoreWebView2Controller* ctrl = static_cast<ICoreWebView2Controller*>(controller);
        ctrl->Close();
        ctrl->Release();
    }
    if (environment != nullptr) {
        ICoreWebView2Environment* env = static_cast<ICoreWebView2Environment*>(environment);
        env->Release();
    }
}