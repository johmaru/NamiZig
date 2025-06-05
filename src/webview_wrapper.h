#ifndef WEBVIEW_WRAPPER_H
#define WEBVIEW_WRAPPER_H

#include <winnt.h>
#ifdef __cplusplus
  #define WIN32_LEAN_AND_MEAN
  #include <windows.h>
  #include <ole2.h>
  #include <oleauto.h>
  #include <objbase.h>
  #include <combaseapi.h>
#else
  #include <stddef.h>
  #include <stdint.h>
  typedef void *HWND;
  typedef long HRESULT;
  typedef unsigned long ULONG;
  typedef struct tagRECT {
    long left;
    long top;
    long right;
    long bottom;
} RECT;

  #define S_OK       ((HRESULT)0L)
  #define E_POINTER  ((HRESULT)0x80004003L)
#endif

#ifdef __cplusplus
extern "C" {
#endif

HRESULT create_webview_environment(void** environment);
HRESULT create_webview_controller(void* environment, HWND hwnd, void** controller);
HRESULT navigate_webview(void* controller, const char* url);
void    resize_webview            (void *controller,  RECT bounds);
void cleanup_webview(void* controller, void* environment);

#ifdef __cplusplus
}
#endif

#endif