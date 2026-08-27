package com.warehouse.domain;

import java.nio.charset.StandardCharsets;

/**
 * A stock-keeping-unit code, normalized to its trimmed form on creation.
 *
 * <p>Only ASCII space, tab, CR, and LF are stripped from the ends. Interior text and case are
 * preserved. The UTF-8 byte length of the normalized code is at most {@link #MAX_UTF8_BYTES}.
 *
 * @param code non-empty normalized stock-keeping-unit code
 */
public record Sku(String code) {

  /** Inclusive UTF-8 byte-length limit of a normalized SKU code. */
  public static final int MAX_UTF8_BYTES = 64;

  /**
   * Strips ASCII edge whitespace and validates the non-empty and byte-length invariants, so every
   * {@code Sku} observed downstream is normalized.
   *
   * @throws InvalidOrderException when the normalized code is empty or longer than {@link
   *     #MAX_UTF8_BYTES} UTF-8 bytes
   */
  public Sku {
    code = stripAsciiEdges(code);
    if (code.isEmpty()) {
      throw new InvalidOrderException("sku code must be non-empty");
    }
    int utf8Bytes = code.getBytes(StandardCharsets.UTF_8).length;
    if (utf8Bytes > MAX_UTF8_BYTES) {
      throw new InvalidOrderException("sku code exceeds " + MAX_UTF8_BYTES + " UTF-8 bytes");
    }
  }

  private static String stripAsciiEdges(String raw) {
    int start = 0;
    int end = raw.length();
    while (start < end && isEdgeWhitespace(raw.charAt(start))) {
      start++;
    }
    while (end > start && isEdgeWhitespace(raw.charAt(end - 1))) {
      end--;
    }
    return raw.substring(start, end);
  }

  private static boolean isEdgeWhitespace(char c) {
    return switch (c) {
      case ' ', '\t', '\r', '\n' -> true;
      default -> false;
    };
  }
}
