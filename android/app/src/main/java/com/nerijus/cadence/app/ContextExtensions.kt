package com.nerijus.cadence.app

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper

/** The activity a view or composable lives in. */
tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
