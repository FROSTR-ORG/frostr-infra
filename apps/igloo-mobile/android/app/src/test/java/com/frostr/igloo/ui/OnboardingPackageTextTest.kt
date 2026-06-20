package com.frostr.igloo.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OnboardingPackageTextTest {
    @Test
    fun line_wrapped_bfonboard_text_is_compacted() {
        val wrapped = "  bfonboard1abc\n  def\tghi\r\njkl  "

        assertEquals(
            "bfonboard1abcdefghijkl",
            normalizeOnboardingPackageText(wrapped),
        )
    }

    @Test
    fun non_package_text_is_only_trimmed_by_default() {
        assertEquals(
            "hello world",
            normalizeOnboardingPackageText("  hello world  "),
        )
    }

    @Test
    fun prefix_required_rejects_non_package_text() {
        assertNull(
            normalizeOnboardingPackageText("  hello world  ", requireBfOnboardPrefix = true),
        )
    }
}
