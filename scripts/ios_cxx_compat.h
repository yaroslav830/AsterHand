// Apple's SDK libc++ expects a global nullptr_t from its compiler's stddef.h.
// Upstream Clang's resource headers no longer supply that Apple-specific alias.
#ifdef __cplusplus
typedef decltype(nullptr) nullptr_t;
#endif
