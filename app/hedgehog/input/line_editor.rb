module Hedgehog
  module Input
    # - Prints prompt
    # - Prints line instance
    # - Manipulates line with user input
    # - Prints autosuggestions
    #
    class LineEditor
      def initialize(handle_teletype: true)
        @handle_teletype = handle_teletype
      end

      # Similarly to the readline library, the aim is to get a line of text.
      #
      # - returns: String, being the line
      #
      def readline(prompt)
        Hedgehog::Teletype.silence! if handle_teletype
        @prompt = prompt
        print("\r")
        print(prompt)
        loop do
          result = handle_character
          return nil if result == :cancel
          if result == :finish
            Hedgehog::Teletype.restore!
            puts ""
            return line
          end
        end
      ensure
        Hedgehog::Teletype.restore! if handle_teletype
        @line = nil
        @suffix = nil
        @cursor_position = nil
        @previous_draw = nil
      end

      private

      # Whether teletype silencing should be managed by this class. This should
      # only be disabled if called from another input source (e.g. Editor).
      #
      attr_reader :handle_teletype

      attr_reader :prompt

      attr_accessor :suffix
      def suffix
        @suffix ||= ""
      end

      def colored_suffix
        str_with_color(suffix, color: 240)
      end

      def stripped_of_color(str)
        str.gsub(/\x1B\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]/, "")
      end

      def size(str)
        stripped_of_color(str).length
      end

      def characters
        @characters ||= Hedgehog::Input::Characters.new
      end

      attr_accessor :line
      def line
        @line ||= ""
      end

      attr_accessor :cursor_position
      def cursor_position
        @cursor_position ||= 0
      end

      attr_accessor :char

      # abc
      #  ^
      # new letter (d) should replace bc with dbc
      #
      def redraw(without_suffix: false)
        previous_draw = @previous_draw || 0

        # line was "hello orld", w typed at 6, cursor incremented by 1
        # line is now "hello world"

        before = cursor_position
        # hello orld
        #        ^ (at 7)

        # Wipe
        #
        print("\r")
        print(" " * previous_draw)

        # Return to beginning
        #
        print("\r")

        # Draw
        #
        print(prompt)
        print(line)
        # hello world
        #            ^ (at 11 == line.length)

        line_size = size(line)
        unless without_suffix
          print(colored_suffix)
          line_size = line_size + size(suffix)
        end

        # Put the cursor back to where it was
        #
        print("\e[D" * [(line_size - before), 0].max)
        # hello world
        #        ^ (<-4 to 7)

        @previous_draw = size(prompt) + size(line) + size(suffix)
      end

      # Make an action based on the input character
      #
      # - Move the cursor
      # - Input a character
      # - Delete a character
      #
      # - returns: true if \n, otherwise false
      def handle_character
        self.char = characters.get_next

        return go_left if char.is?(:left)
        return go_right if char.is?(:right)
        return :cancel if char.is?(:ctrl_d)
        return interrupt if char.is?(:ctrl_c)
        return backspace if char.is?(:backspace)
        return :finish if char.is?(:enter)
        return auto_complete if char.is?(:tab)

        return if char.unknown? || char.known_special?

        line.insert(cursor_position, char)
        self.cursor_position = cursor_position + 1
        redraw
      end

      def go_left(by: 1)
        return if cursor_position - by < 0
        self.cursor_position = cursor_position - by
        by.times { print(char.to_s) }
      end

      def go_right
        return if cursor_position > line.length - 1
        self.cursor_position = cursor_position + 1
        print(char.to_s)
      end

      def backspace
        go_left
        line[cursor_position] = ''
        redraw
      end

      def interrupt
        return unless line.present?
        redraw(without_suffix: true)
        print(str_with_color("^C", color: 0, bg_color: 15))
        raise Interrupt
      end

      def str_with_color(str, color: nil, bg_color: nil)
        color = "\x1b[38;5;#{color}m" if color
        bg_color = "\x1b[48;5;#{bg_color}m" if bg_color
        reset = "\x1b[0m"
        "#{color}#{bg_color}#{str}#{reset}"
      end

      def auto_complete
        complete_proc = if line.include?(" ")
                          nil
                        else
                          Hedgehog::Input::Choice::PATH_BINARY_PROC
                        end

        current_word, range = current_word_and_range

        result = Hedgehog::Input::Choice
          .new(handle_teletype: false, completion_proc: complete_proc)
          .read_choice(current_word, size(prompt) + range.last)

        if result
          line[range] = result
          self.cursor_position = range.first + result.length
        else
          self.cursor_position = range.last + 1
        end

        redraw
      end

      # The word that the cursor is on and the character it starts on.
      #
      # For example
      #   01234567890
      #   hello world
      #          ^
      # would return ["world", 6..10]
      #
      def current_word_and_range
        words = line.split(Hedgehog::Command::UNESCAPED_WORD_REGEX)

        iterated_chars = 0
        this_is_the_word = false
        words.each do |word|
          word_started_on = iterated_chars
          word.each_char do |char|
            this_is_the_word = true if iterated_chars == cursor_position - 1
            iterated_chars = iterated_chars + 1
          end
          word_ended_on = iterated_chars - 1
          return [word, word_started_on..word_ended_on] if this_is_the_word

          # For the space character
          iterated_chars = iterated_chars + 1
        end
        return ["", cursor_position..cursor_position]
      end
    end
  end
end
