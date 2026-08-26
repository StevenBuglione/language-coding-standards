package com.badexamples.format;

/** Deliberate google-java-format violation: this file is not GJF-clean. */
public final class Misformatted {

      private final String value;

   /**
    * Wraps the given value.
    *
    * @param value the value to store
    */
    public Misformatted( String value ) {
          this.value = value;
   }

   /**
    * Returns the stored value.
    *
    * @return the value
    */
  public String value() { return value; }
}
