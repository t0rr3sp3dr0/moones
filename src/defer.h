//
// Created by Pedro Tôrres on 2025-01-25.
//

#ifndef _MOONES_DEFER_H
#define _MOONES_DEFER_H

#define _DEFER_PRAGMA(S) _Pragma(#S)
#define _DEFER_STRCAT(LHS, RHS) LHS ## RHS
#define _DEFER_INVOKE(F, ...) F(__VA_ARGS__)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdollar-in-identifier-extension"
#define _DEFER_UNIQ _DEFER_INVOKE(_DEFER_STRCAT, _defer$, __COUNTER__)
#pragma clang diagnostic pop

#define _DEFER_DECL __attribute__((cleanup(_defer_delete))) _defer_t _DEFER_UNIQ =

#define DEFER                                                   \
    _DEFER_PRAGMA(clang diagnostic push)                        \
    _DEFER_PRAGMA(clang diagnostic ignored "-Wunused-variable") \
    _DEFER_DECL                                                 \
    _DEFER_PRAGMA(clang diagnostic pop)

typedef void (^_defer_t)(void);

__attribute__((always_inline)) static inline void _defer_delete(_defer_t *this) {
    (*this)();
}

#endif	// _MOONES_DEFER_H
