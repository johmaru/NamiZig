#include <intsafe.h>
#include <shlobj_core.h>
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
  #include <shlobj.h>
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
    HRESULT create_webview_controller(void* environment, HWND hwnd, void** controller, controllerSettings settings);
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
            [controller, hwnd, hEvent, &callback_hr,settings](HRESULT result, ICoreWebView2Controller* ctrl) -> HRESULT {

                OutputDebugStringA("CreateCoreWebView2Controller COMPLETED HANDLER called.\n");
                char buffer[256];
                sprintf_s(buffer, sizeof(buffer), "  Callback Result HRESULT: 0x%lX\n", result);
                OutputDebugStringA(buffer);
                if (ctrl != nullptr) {
                    sprintf_s(buffer, sizeof(buffer), "  Controller pointer: %p\n", ctrl);
                    OutputDebugStringA(buffer);
                } else {
                    OutputDebugStringA("  Controller pointer is NULL.\n");
                }

                callback_hr = result;

                if (SUCCEEDED(result) && ctrl != nullptr) {
                    if (ctrl != nullptr) {
                        sprintf_s(buffer, sizeof(buffer), "  Controller pointer: %p\n", ctrl);
                        OutputDebugStringA(buffer);
                    } else {
                        OutputDebugStringA("  Controller pointer is NULL (FAILED result).\n");
                    }
                        *controller = ctrl;
                        ctrl->AddRef();

                        sprintf_s(buffer, sizeof(buffer), "  *controller set to: %p\n", *controller);
                        OutputDebugStringA(buffer);

                        if (settings.contextMenu) {
                            ComPtr<ICoreWebView2> webview;
                            HRESULT hr = ctrl->get_CoreWebView2(&webview);
                            if (SUCCEEDED(hr) && webview != nullptr) {
                                ComPtr<ICoreWebView2Settings> webview_settings;
                                HRESULT hr_settings = webview->get_Settings(&webview_settings);
                                if (SUCCEEDED(hr_settings) && webview_settings != nullptr) {
                                    webview_settings->put_AreDefaultContextMenusEnabled(TRUE);
                                    OutputDebugStringA("Context menu enabled.\n");
                                } else {
                                    OutputDebugStringA("Failed to get WebView2 settings.\n");
                                }
                            }
                        } else {
                            ComPtr<ICoreWebView2> webview;
                            HRESULT hr = ctrl->get_CoreWebView2(&webview);
                            if (SUCCEEDED(hr) && webview != nullptr) {
                                ComPtr<ICoreWebView2Settings> webview_settings;
                                HRESULT hr_settings = webview->get_Settings(&webview_settings);
                                if (SUCCEEDED(hr_settings) && webview_settings != nullptr) {
                                    webview_settings->put_AreDefaultContextMenusEnabled(FALSE);
                                    OutputDebugStringA("Context menu disabled.\n");
                                } else {
                                    OutputDebugStringA("Failed to get WebView2 settings.\n");
                                }
                            }
                        }

                        if (settings.isVirtualHost) {
                            ComPtr<ICoreWebView2> webview;
                            HRESULT hr = ctrl->get_CoreWebView2(&webview);

                            if (SUCCEEDED(hr) && webview != nullptr) {

                                ComPtr<ICoreWebView2_11> webview11;
                                hr = webview->QueryInterface(IID_PPV_ARGS(&webview11));

                                if (SUCCEEDED(hr) && webview11 != nullptr) {
                                    LPCWSTR hostName = L"assets.namizig.com";

                                    WCHAR documentPath[MAX_PATH];
                                    HRESULT hr_folder = SHGetFolderPathW(
                                        NULL, 
                                        CSIDL_PERSONAL,
                                        NULL, 
                                        0, 
                                        documentPath
                                    );

                                    if (SUCCEEDED(hr_folder)) {
                                        const wchar_t* subFolder = L"\\NamiZig";
                                        size_t docPathLen = wcslen(documentPath);
                                        size_t subFolderLen = wcslen(subFolder);
                                        size_t folderPathLen = docPathLen + subFolderLen + 1;
                                        wchar_t* folderPath = new (std::nothrow) wchar_t[folderPathLen];
                                        if (folderPath != nullptr) {
                                            swprintf_s(folderPath, folderPathLen, L"%s%s", documentPath, subFolder);

                                            if (CreateDirectoryW(folderPath, NULL)) {
                                                DWORD error = GetLastError();
                                                if (error != ERROR_ALREADY_EXISTS) {
                                                    char err_buffer[256];
                                                    sprintf_s(err_buffer, sizeof(err_buffer), "Failed to create directory: %ls. Error: %lu\n", folderPath, error);
                                                    OutputDebugStringA(err_buffer);
                                                } else {
                                                
                                                }
                                            } else {
                            
                                            }

                                            hr = webview11->SetVirtualHostNameToFolderMapping(
                                                hostName,
                                                folderPath,
                                                COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW
                                            );
                                            delete[] folderPath;

                                            if (SUCCEEDED(hr)) {
                                                OutputDebugStringA("Virtual host name mapping set successfully.\n");
                                            } else {
                                                char err_buffer[256];
                                                sprintf_s(err_buffer, sizeof(err_buffer), "Failed to set virtual host name mapping. HRESULT: 0x%lX\n", hr);
                                                OutputDebugStringA(err_buffer);
                                            }
                                        } else {
                                            OutputDebugStringA("Failed to allocate memory for folder path.\n");
                                        }
                                    } else {
                                        char err_buffer[256];
                                        sprintf_s(err_buffer, sizeof(err_buffer), "Failed to get Documents folder. HRESULT: 0x%lX\n", hr_folder);
                                        OutputDebugStringA(err_buffer);
                                    }
                                } else {
                                    char err_buffer[256];
                                    sprintf_s(err_buffer, sizeof(err_buffer), "ICoreWebView2_11 not supported. Virtual host feature unavailable. HRESULT: 0x%lX\n", hr);
                                    OutputDebugStringA(err_buffer);
                                }
                            }
                        }
                        
                } else {
                    *controller = nullptr;
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
        OutputDebugStringA("create_webview_controller: final_hr indicates failure, but *controller_out was set. Cleaning up.\n");
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