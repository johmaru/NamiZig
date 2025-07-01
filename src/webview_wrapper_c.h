#ifndef WEBVIEW_WRAPPER_C_H
#define WEBVIEW_WRAPPER_C_H

#ifdef __cplusplus
    #include <Windows.h>
#endif
#include <stdbool.h>
typedef struct controllerSettings {
    bool contextMenu;
    bool isVirtualHost;
    const char *virtualHostName;
    const char *htmlContent;
} controllerSettings;

typedef void (*WebMessageReceivedCallback)(const char* message_json);

 
#ifndef __cplusplus
typedef unsigned short wchar_t;
typedef void* HWND;
typedef long  HRESULT;

typedef struct tagRECT {
    long left;
    long top;
    long right;
    long bottom;
} RECT;
#endif // !__cplusplus

#ifdef WEBVIEW_WRAPPER_EXPORTS
#  define WEBVIEW_API __declspec(dllexport)
#else
#  define WEBVIEW_API __declspec(dllimport)
#endif


#ifdef __cplusplus
extern "C" {
#endif

WEBVIEW_API HRESULT create_webview_environment(void **environment);
WEBVIEW_API HRESULT create_webview_controller (void *environment, HWND hwnd, void **controller, controllerSettings settings);
WEBVIEW_API HRESULT navigate_webview          (void *controller,  const char *url);
WEBVIEW_API void    resize_webview            (void *controller,  RECT bounds);
WEBVIEW_API void     cleanup_webview           (void *controller,  void *environment);
WEBVIEW_API HRESULT register_web_message_handler(void *controller, WebMessageReceivedCallback callback);
WEBVIEW_API HRESULT execute_script            (void *controller,  const char *script);
WEBVIEW_API HRESULT __stdcall wrapper_SetWindowTheme(HWND hwnd, const wchar_t *pszSubAppName, const wchar_t *pszSubIdList);

extern const unsigned int WRAPPER_TBN_DROPDOWN;
extern const unsigned int WRAPPER_NM_CUSTOMDRAW;

#ifdef __cplusplus
}
#endif

#endif