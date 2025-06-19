#ifndef WEBVIEW_WRAPPER_C_H
#define WEBVIEW_WRAPPER_C_H

#include <stdbool.h>
typedef struct controllerSettings {
    bool contextMenu;
    bool isVirtualHost;
    const char *virtualHostName;
} controllerSettings;

 
#ifndef __cplusplus
typedef unsigned short wchar_t;
typedef void *HWND;
typedef long  HRESULT;
typedef unsigned long ULONG;

typedef struct tagRECT {
    long left;
    long top;
    long right;
    long bottom;
} RECT;
#define S_OK      ((HRESULT)0L)
#define E_POINTER ((HRESULT)0x80004003L)
#else
#include <windows.h>
#endif // !__cplusplus

#ifdef WEBVIEW_WRAPPER_EXPORTS
#  define WEBVIEW_API __declspec(dllexport)
#else
#  define WEBVIEW_API __declspec(dllimport)
#endif


#ifdef __cplusplus
extern "C" {
#endif

HRESULT create_webview_environment(void **environment);
HRESULT create_webview_controller (void *environment, HWND hwnd, void **controller, controllerSettings settings);
HRESULT navigate_webview          (void *controller,  const char *url);
void    resize_webview            (void *controller,  RECT bounds);
void     cleanup_webview           (void *controller,  void *environment);
WEBVIEW_API HRESULT __stdcall wrapper_SetWindowTheme(HWND hwnd, const wchar_t *pszSubAppName, const wchar_t *pszSubIdList);

extern const unsigned int WRAPPER_TBN_DROPDOWN;
extern const unsigned int WRAPPER_NM_CUSTOMDRAW;

#ifdef __cplusplus
}
#endif

#endif