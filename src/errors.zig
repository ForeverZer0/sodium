const std = @import("std");

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

/// Error set for incorrect input given by a user.
pub const UserError = error{
    /// A required argument for a flag was missing.
    MissingArgument,
    /// The given argument was not valid for the flag.
    InvalidArgument,
    /// An undefined flag name was specified.
    UnknownFlag,
} || ParseError;

/// Set of errors used throughout the library.
pub const Error = error{
    /// A required string value was empty or only whitespace.
    EmptyString,
    /// An invalid character in a string.
    InvalidFlagName,
    /// A shorthand value is not an ASCII letter (a-z or A-Z).
    InvalidShorthand,
    /// A flag with the same name/alias is already defined.
    DuplicateName,
    /// A flag with the same shorthand value is already defined.
    DuplicateShorthand,
    /// An attempt to convert a string into the incorrect type.
    TypeMismatch,
    /// The user has used the undefined "help" command.
    /// This is typically not an actual "error", but is used as a signal to callers.
    HelpRequested,
} || std.mem.Allocator.Error || UserError;
