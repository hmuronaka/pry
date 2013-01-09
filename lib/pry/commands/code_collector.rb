class Pry
  class Command::CodeCollector
    include Helpers::CommandHelpers

    attr_accessor :args
    attr_accessor :opts
    attr_accessor :_pry_

    def initialize(args, opts, _pry_)
      @args = args
      @opts = opts
      @_pry_ = _pry_
    end

    # Add the `--lines`, `-o`, `-i`, `-s`, `-d` options.
    def self.inject_options(opt)
      opt.on :l, :lines, "Restrict to a subset of lines. Takes a line number or range",
                         :optional_argument => true, :as => Range, :default => 1..-1
      opt.on :o, :out,   "Select lines from Pry's output result history. Takes an index or range",
                         :optional_argument => true, :as => Range, :default => -5..-1
      opt.on :i, :in,    "Select lines from Pry's input expression history. Takes an index or range",
                         :optional_argument => true, :as => Range, :default => -5..-1
      opt.on :s, :super, "Select the 'super' method. Can be repeated to traverse the ancestors",
                         :as => :count
      opt.on :d, :doc,   "Select lines from the code object's documentation"
    end

    # The content (i.e code/docs) for the selected object.
    # If the user provided a bare code object, it returns the source.
    # If the user provided the `-i` or `-o` switches, it returns the
    # selected input/output lines joined as a string. If the user used
    # `-d CODE_OBJECT` it returns the docs for that code object.
    #
    # @return [String]
    def content
      return @content if @content
      raise CommandError, "Only one of --out, --in, --doc and CODE_OBJECT may be specified." if bad_option_combination?

      content = case
                when opts.present?(:o)
                  pry_output_content
                when opts.present?(:i)
                  pry_input_content
                when opts.present?(:d)
                  code_object.doc
                else
                  code_object_source_or_file
                end

      @content ||= restrict_to_lines(content, line_range)
    end

    # The code object
    #
    # @return [Pry::WrappedModule, Pry::Method, Pry::Command]
    def code_object
      Pry::CodeObject.lookup(obj_name, _pry_.current_context, _pry_,  :super =>  opts[:super])
    end

    # Given a string and a range, return the `range` lines of that
    # string.
    #
    # @param [String] content
    # @param [Range, Fixnum] range
    # @return [String] The string restricted to the given range
    def restrict_to_lines(content, range)
      Array(content.lines.to_a[range]).join
    end

    # The selected `_pry_.output_array` as a string, as specified by
    # the `-o` switch.
    #
    # @return [String]
    def pry_output_content
      pry_array_content_as_string(_pry_.output_array, opts[:o]) do |v|
        Pry.config.gist.inspecter.call(v)
      end
    end

    # The selected `_pry_.input_array` as a string, as specified by
    # the `-i` switch.
    #
    # @return [String]
    def pry_input_content
      pry_array_content_as_string(_pry_.input_array, opts[:i]) { |v| v }
    end

    # The line range passed to `--lines`
    def line_range
      opts.present?(:lines) ? one_index_range_or_number(opts[:lines]) : 0..-1
    end

    private

    def bad_option_combination?
      [opts.present?(:in), opts.present?(:out),
       !args.empty?].count(true) > 1
    end

    def pry_array_content_as_string(array, range, &block)
      raise CommandError, "Minimum value for range is 1, not 0." if convert_to_range(range).first == 0

      array = Array(array[range]) || []
      all = ''
      array.each { |v| all << block.call(v) }
      all
    end

    def code_object_source_or_file
      (code_object && code_object.source) || file_content
    end

    def file_content
      if File.exists?(obj_name)
        File.read(obj_name)
      else
        could_not_locate(obj_name)
      end
    end

    def could_not_locate(name)
      raise CommandError, "Cannot locate: #{name}!"
    end

    def convert_to_range(n)
      if !n.is_a?(Range)
        (n..n)
      else
        n
      end
    end

    def obj_name
      @obj_name ||= args.empty? ? no_arg : args.join(" ")
    end
  end
end