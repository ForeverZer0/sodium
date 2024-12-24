/// Error set for string-parsing related errors.
pub const ParseError = error{
    /// An empty string was given.
    EmptyString,
    /// The number of given items is less than the size of an array/vector.
    NotEnoughItems,
    /// The number of items exceeds the size of an array/vector.
    TooManyItems,
    /// The result cannot fit in the type specified.
    Overflow,
    /// The input was empty or contained an invalid character, or decoding a UTF-8 codepoint failed.
    InvalidCharacter,
    /// A field name was not found in an enum.
    InvalidEnumName,
    /// A numeric value does not match a named field value in an enum,
    /// and the enum is not marked non-exhaustive.
    InvalidEnumTag,
};
