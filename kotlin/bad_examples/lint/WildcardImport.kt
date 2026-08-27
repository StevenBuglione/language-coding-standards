package com.badexamples.lint

import java.util.*

/** Deliberate ktlint style violation: wildcard import. */
class WildcardImport {
    fun names(): List<String> {
        val items = ArrayList<String>()
        items.add("sku")
        return items
    }
}
