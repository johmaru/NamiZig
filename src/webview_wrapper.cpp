#if defined(_M_X64) && !defined(_M_AMD64)
#define _M_AMD64 _M_X64
#endif
#if defined(_M_AMD64) && !defined(_AMD64_)
#define _AMD64_
#endif

#ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
/* #include <intsafe.h>
#include <strsafe.h>
#include <synchapi.h>
#include <winbase.h>
#include <winerror.h>
#include <winnt.h>
#include <winuser.h> */
#endif
  #include <windows.h>

  #include <synchapi.h>
  #include <winbase.h>
  #include <winuser.h>

  #include <stdio.h>

#ifdef __cplusplus
  
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

#include <cstddef>

#include <WebView2EnvironmentOptions.h>
#include <WebView2.h>

#include "webview_wrapper_c.h"


#ifdef __cplusplus
using namespace Microsoft::WRL;
#endif


extern "C" {
    HRESULT create_webview_environment(void** environment);
    HRESULT create_webview_controller(void* environment, HWND hwnd, void** controller);
    HRESULT navigate_webview(void* controller_in, const char* url_utf8);
    void resize_webview(void* controller_in, RECT bounds);
    void cleanup_webview(void* controller, void* environment);
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

    HRESULT hr_async_start = CreateCoreWebView2EnvironmentWithOptions(
        nullptr, // browserExecutableFolder
        nullptr, // userDataFolder
        nullptr, // environmentOptions
        Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [environment,hEvent,&callback_hr](HRESULT result, ICoreWebView2Environment* env) -> HRESULT {
                callback_hr = result;
                if (SUCCEEDED(result) && env != nullptr) {
                    *environment = env;
                    env->AddRef();
                } else {
                    *environment = nullptr;
                }
                SetEvent(hEvent);
                return result;
            }
        ).Get()
    );

    HRESULT final_hr;
    if (SUCCEEDED(hr_async_start)) {
        DWORD wait_result;
        for (;;) {
            wait_result = MsgWaitForMultipleObjects(1, &hEvent, FALSE, 30000, QS_ALLINPUT);

            if (wait_result == WAIT_OBJECT_0 
                || wait_result == WAIT_FAILED
                || wait_result == WAIT_TIMEOUT) {
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
    }
    CloseHandle(hEvent);
    return final_hr;
    #else
    return E_NOTIMPL;
    #endif
}

HRESULT create_webview_controller(void* environment, HWND hwnd, void** controller) {
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
    HRESULT hr_async_start = env->CreateCoreWebView2Controller(
        hwnd,
        Microsoft::WRL::Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
            [controller, hwnd, hEvent, &callback_hr](HRESULT result, ICoreWebView2Controller* ctrl) -> HRESULT {

                OutputDebugStringA("CreateCoreWebView2Controller COMPLETED HANDLER called.\n");
                char buffer[256];
                sprintf_s(buffer, sizeof(buffer), "  Result HRESULT: 0x%lX\n", result);
                OutputDebugStringA(buffer);
                if (ctrl != nullptr) {
                    sprintf_s(buffer, sizeof(buffer), "  Controller pointer: %p\n", ctrl);
                    OutputDebugStringA(buffer);
                } else {
                    OutputDebugStringA("  Controller pointer is NULL.\n");
                }

                callback_hr = result;

                if (SUCCEEDED(result)) {
                    if (ctrl != nullptr) {
                        *controller = ctrl;
                        ctrl->AddRef();
                    } else {
                        callback_hr = E_FAIL;
                        *controller = nullptr;
                    }
                } else {
                    *controller = nullptr;
                }
                SetEvent(hEvent);
                return result;
            }
        ).Get()
    );

    HRESULT final_hr;
    if (SUCCEEDED(hr_async_start)) {
        DWORD wait_result;
        for (;;) {
            wait_result = MsgWaitForMultipleObjects(1, &hEvent, FALSE, 30000, QS_ALLINPUT);

            if (wait_result == WAIT_OBJECT_0 
                || wait_result == WAIT_FAILED
                || wait_result == WAIT_TIMEOUT) {
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
    }
    CloseHandle(hEvent);
    return final_hr;
    #else
    return S_OK;
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