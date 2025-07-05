#ifndef WEBVIEW_WRAPPER_C_H
#define WEBVIEW_WRAPPER_C_H


typedef void* HWND_HANDLE;


#ifndef __cplusplus
    typedef long HRESULT;
    typedef unsigned short wchar_t;
    typedef struct tagRECT {
        long left;
        long top;
        long right;
        long bottom;
    } RECT;
#endif

#include <stdbool.h>
typedef struct controllerSettings {
    bool contextMenu;
    bool isVirtualHost;
    const char *virtualHostName;
    const char *htmlContent;
} controllerSettings;

#ifdef _WIN32
#define NAMI_API_CALL __stdcall
#else
#define NAMI_API_CALL
#endif

typedef void (NAMI_API_CALL *WebMessageReceivedCallback)(HWND_HANDLE hwnd, const char* message_json);
typedef void (NAMI_API_CALL *WebViewCreatedCallback)(HRESULT hr, void* controller, void* context);

 
#ifdef WEBVIEW_WRAPPER_EXPORTS
#  define WEBVIEW_API __declspec(dllexport)
#else
#  define WEBVIEW_API __declspec(dllimport)
#endif


#ifdef __cplusplus
extern "C" {
#endif

WEBVIEW_API HRESULT create_webview_environment(void **environment);
WEBVIEW_API HRESULT create_webview_controller_async(void *environment, HWND_HANDLE hwnd, const controllerSettings* settings, WebViewCreatedCallback on_completed, void* context);
WEBVIEW_API HRESULT navigate_webview          (void *controller,  const char *url);
WEBVIEW_API void    resize_webview            (void *controller,  RECT bounds);
WEBVIEW_API void    cleanup_webview           (void *controller,  void *environment);
WEBVIEW_API HRESULT register_web_message_handler(void* controller_in, WebMessageReceivedCallback callback);
WEBVIEW_API HRESULT execute_script            (void *controller,  const char *script);
WEBVIEW_API HRESULT __stdcall wrapper_SetWindowTheme(HWND_HANDLE hwnd, const wchar_t *pszSubAppName, const wchar_t *pszSubIdList);
WEBVIEW_API HRESULT setup_accelerator_handler(void* controller);

extern const unsigned int WRAPPER_TBN_DROPDOWN;
extern const unsigned int WRAPPER_NM_CUSTOMDRAW;

#ifdef __cplusplus
}
#endif

#endif