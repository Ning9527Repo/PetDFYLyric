// RootHide-compatible substrate ABI declarations.
#pragma once
#include <objc/runtime.h>
#ifdef __cplusplus
extern "C" {
#endif
void MSHookMessageEx(Class cls, SEL sel, IMP replacement, IMP *original);
void MSHookFunction(void *symbol, void *replacement, void **original);
void *MSFindSymbol(const void *image, const char *name);
const void *MSGetImageByName(const char *path);
#ifdef __cplusplus
}
#endif
