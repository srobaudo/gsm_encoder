# frozen_string_literal: true
# encoding: utf-8

# Stealing from Twitter's Java implementation
# https://github.com/twitter/cloudhopper-commons-charset/blob/master/src/main/java/com/cloudhopper/commons/charset/GSMCharset.java

#
# This class encodes and decodes Ruby Strings to and from the SMS default
# alphabet. It also supports the default extension table. The default alphabet
# and it's extension table is defined in GSM 03.38.
module GSMEncoder
  BASIC_CHARSET = :basic
  SPANISH_CHARSET = :spanish

  DEFAULT_REPLACE_CHAR = '?'

  EXTENDED_ESCAPE = 0x1b
  NL = 10.chr
  CR = 13.chr
  BS = 92.chr

  CHAR_TABLE = [
    '@', '£', '$', '¥', 'è', 'é', 'ù', 'ì',
    'ò', 'Ç',  NL, 'Ø', 'ø', CR , 'Å', 'å',
    'Δ', '_', 'Φ', 'Γ', 'Λ', 'Ω', 'Π', 'Ψ',
    'Σ', 'Θ', 'Ξ', " ", 'Æ', 'æ', 'ß', 'É', # 0x1B is actually an escape which we'll encode to a space char
    " ", '!', '"', '#', '¤', '%', '&', "'",
    '(', ')', '*', '+', ',', '-', '.', '/',
    '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', ':', ';', '<', '=', '>', '?',
    '¡', 'A', 'B', 'C', 'D', 'E', 'F', 'G',
    'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
    'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W',
    'X', 'Y', 'Z', 'Ä', 'Ö', 'Ñ', 'Ü', '§',
    '¿', 'a', 'b', 'c', 'd', 'e', 'f', 'g',
    'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w',
    'x', 'y', 'z', 'ä', 'ö', 'ñ', 'ü', 'à',
  ].join # make it string to speedup lookup

  # Extended character table. Characters in this table are accessed by the
  # 'escape' character in the base table. It is important that none of the
  # 'inactive' characters ever be matchable with a valid base-table
  # character as this breaks the encoding loop.
  BASIC_EXT_CHAR_TABLE = [
    0,   0,   0, 0, 0,   0,   0, 0, 0,   0,   0, 0, 0,   0,   0,   0,
    0,   0,   0, 0, '^', 0,   0, 0, 0,   0,   0, 0, 0,   0,   0,   0,
    0,   0,   0, 0, 0,   0,   0, 0, '{', '}', 0, 0, 0,   0,   0,   BS,
    0,   0,   0, 0, 0,   0,   0, 0, 0,   0,   0, 0, '[', '~', ']', 0,
    '|', 0,   0, 0, 0,   0,   0, 0, 0,   0,   0, 0, 0,   0,   0,   0,
    0,   0,   0, 0, 0,   0,   0, 0, 0,   0,   0, 0, 0,   0,   0,   0,
    0,   0,   0, 0, 0,   '€', 0, 0, 0,   0,   0, 0, 0,   0,   0,   0,
    0,   0,   0, 0, 0,   0,   0, 0, 0,   0,   0, 0, 0,   0,   0,   0,
  ]
  SPANISH_EXT_CHAR_TABLE = [
    0,   0,   0, 0, 0,   0,   0, 0, 0,   'ç', 0, 0, 0,   0,   0,   0,
    0,   0,   0, 0, '^', 0,   0, 0, 0,   0,   0, 0, 0,   0,   0,   0,
    0,   0,   0, 0, 0,   0,   0, 0, '{', '}', 0, 0, 0,   0,   0,   BS,
    0,   0,   0, 0, 0,   0,   0, 0, 0,   0,   0, 0, '[', '~', ']', 0,
    '|', 'Á', 0, 0, 0,   0,   0, 0, 0,   'Í', 0, 0, 0,   0,   0,   'Ó',
    0,   0,   0, 0, 0,   'Ú', 0, 0, 0,   0,   0, 0, 0,   0,   0,   0,
    0,   'á', 0, 0, 0,   '€', 0, 0, 0,   'í', 0, 0, 0,   0,   0,   'ó',
    0,   0,   0, 0, 0,   'ú', 0, 0, 0,   0,   0, 0, 0,   0,   0,   0,
  ]

  BASIC_REGEX = /\A[ -_a-~#{Regexp.escape(CHAR_TABLE + BASIC_EXT_CHAR_TABLE.select {|c| c != 0}.join)}]*\Z/
  SPANISH_REGEX = /\A[ -_a-~#{Regexp.escape(CHAR_TABLE + SPANISH_EXT_CHAR_TABLE.select {|c| c != 0}.join)}]*\Z/

  BASIC_CHAR_REGEX = /[#{ Regexp.escape(BASIC_EXT_CHAR_TABLE.select(&:nonzero?).join) }]{1}/

  # Verifies that this charset can represent every character in the Ruby
  # String.
  # @param str The String to verfiy
  # @return True if the charset can represent every character in the Ruby
  #   String, otherwise false.
  def can_encode?(str, charset: BASIC_CHARSET)
    !str || !!(regex(charset) =~ str)
  end

  def encode(str, replace_char: DEFAULT_REPLACE_CHAR, charset: BASIC_CHARSET)
    return nil unless str
    replace_char = DEFAULT_REPLACE_CHAR unless replace_char && can_encode?(replace_char, charset: charset)

    buffer = ''.encode('binary')

    begin
      str.each_char do |c|
        if index = CHAR_TABLE.rindex(c)
          buffer << index
        elsif index = ext_char_table(charset).index(c)
          buffer << EXTENDED_ESCAPE
          buffer << index
        else
          buffer << replace_char
        end
      end
    rescue
      # TODO: ?
    end
    buffer
  end

  def decode(bstring, charset: BASIC_CHARSET)
    return nil unless bstring

    buffer = ''.encode('utf-8')

    table = CHAR_TABLE
    bstring.bytes.each do |c|
      code = c & 0x000000ff
      if code == EXTENDED_ESCAPE
        # take next char from extension table
        table = ext_char_table(charset)
      else
        buffer << (code >= table.length ? '?' : table[code])
        # go back to the default table
        table = CHAR_TABLE
      end
    end
    buffer
  end

  # Public: This method splits an SMS's text into chunks based on GSM 03.38 specification
  # assuming use of basic extension table, and considering support for Spanish characters
  # by switching encoding to UCS-2 instead of 7-bit GSM.
  #
  # If UCS-2 encoding is used, then maximum message size is 70 characters.
  # If characters from the basic extension table are used, then an escape character is appended
  # to the message for each of those characters, and needs to be accounted for when splitting.
  # If use_rolling_split: false; a naive (but fast) approach for splitting is used, assuming that
  # the whole of special characters could be present in any of the chunks (and all of them).
  # If use_rolling_split: true; a greedy approach is used, processing one word at a time, and
  # fitting as many words as possible in each message.
  def split_sms(sms, use_rolling_split: false)
    if spanish_specific?(sms) # it means UCS-2 encoding will be used instead of 7-bit GSM
      sms.gsub(/(.{1,70})( |\Z)/, "\\1\n").split("\n")
    elsif use_rolling_split # do smarter split by processing one word at a time
      rolling_split(sms)
    else # we need to account for escape character among the 160 chars
      safe_length = 160 - escaped_character_count(sms) # assume all special characters are in same partition
      sms.gsub(/(.{1,#{safe_length}})( |\Z)/, "\\1\n").split("\n")
    end
  end

  module_function :can_encode?
  module_function :encode
  module_function :decode
  module_function :split_sms

private

  def regex(charset)
    case charset
    when SPANISH_CHARSET then SPANISH_REGEX
    else BASIC_CHARSET
    end
  end

  def ext_char_table(charset)
    case charset
    when SPANISH_CHARSET then SPANISH_EXT_CHAR_TABLE
    else BASIC_EXT_CHAR_TABLE
    end
  end

  def requires_escaping?(str)
    str && (SPANISH_REGEX =~ str)
  end

  def spanish_specific?(str)
    requires_escaping?(str) && !(BASIC_EXT_CHAR_TABLE =~ str)
  end

  def escaped_character_count(str)
    str.scan(BASIC_CHAR_REGEX).size
  end

  def rolling_split(sms)
    available = 160
    current = 0
    sms.split(/[\n\s]/).each_with_object([]) do |word, result|
      # +2 to account for space between words - which is an extension table character also
      length = word.size + escaped_character_count(word) + 2
      available -= length
      if available.negative?
        current += 1
        available = 160 - length
      end

      result[current] = [result[current], word].compact.join(" ")
    end.compact
  end
end
