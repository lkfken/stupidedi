module Stupidedi
  module Builder

    class BuilderDsl
      include Inspect

      SEGMENT_ID = /^[A-Z][A-Z0-9]{1,2}$/

      def initialize(config)
        @machine = StateMachine.build(config)
        @reader  = DslReader.new(Reader::Separators.empty,
                                 Reader::SegmentDict.empty)
      end

      # @return [Array<InstructionTable>]
      def successors
        @machine.states.inject([]) do |list, s|
          list << s.instructions
        end
      end

      #########################################################################
      # @group Element Constructors

      # Generates a repeated element (simple or composite)
      def repeated(*elements)
        :repeated.cons(elements.cons)
      end

      # Generates a composite element
      def composite(*components)
        :composite.cons(components.cons)
      end

      # @endgroup
      #########################################################################

      #########################################################################
      # @group Element Placeholders

      # Generates a blank element
      #
      # @return [void]
      def blank
        nil
      end

      # @see Schema::ElementReq#forbidden?
      #
      # @return [void]
      def not_used
        @__not_used ||= :not_used.cons
      end

      # @see Schema::SimpleElementUse#allowed_values
      #
      # @return [void]
      def default
        @__default ||= :default.cons
      end

      # @endgroup
      #########################################################################

      # @return [void]
      def pretty_print(q)
        q.pp @machine
      end

      # @return [BuilderDsl]
      def segment!(name, *args)
        @reader = @machine.input!(segment_tok(name, args), @reader)

        if @machine.stuck?
          raise Exceptions::ParseError,
            "Segment #{name} cannot occur here"
        end

        self
      end

      # @return [Values::AbstractVal]
      def value
        @machine.value
      end

      def pinch
        @machine.pinch
      end

    private

      def method_missing(name, *args)
        if SEGMENT_ID =~ name.to_s
          segment!(name, *args)
        else
          super
        end
      end

      #########################################################################
      # @group TokenVal Constructors

      # @return [Reader::SegmentTok]
      def segment_tok(id, elements)
        element_toks = []

        unless @reader.segment_dict.defined_at?(id)
          element_idx  = "00"
          elements.each do |e_tag, e_val|
            element_idx.succ!

            unless e_val.nil?
              raise Exceptions::ParseError,
                "#{id}#{element_idx} is a simple element"
            end

            element_toks << simple_tok(e_tag)
          end
        else
          segment_def  = @reader.segment_dict.at(id)
          element_uses = segment_def.element_uses

          if elements.length > element_uses.length
            raise Exceptions::ParseError,
              "#{id} has only #{element_uses.length} elements"
          end

          element_idx  = "00"
          element_uses.zip(elements) do |e_use, (e_tag, e_val)|
            element_idx.succ!
            designator = "#{id}#{element_idx}"

            if e_use.repeatable?
              # Repeatable composite or non-composite
              unless e_tag == :repeated or (e_tag.blank? and e_val.blank?)
                raise Exceptions::ParseError,
                  "#{designator} is a repeatable element"
              end

              element_toks << repeated_tok(e_val || [], e_use, designator)
            elsif e_use.composite?
              unless e_tag == :composite or (e_tag.blank? and e_val.blank?)
                raise Exceptions::ParseError,
                  "#{id}#{element_idx} is a non-repeatable composite element"
              end

              element_toks << composite_tok(e_val || [], e_use, designator)
            else
              # The actual value is in e_tag
              unless e_val.nil?
                raise Exceptions::ParseError,
                  "#{id}#{element_idx} is a non-repeatable simple element"
              end

              element_toks << simple_tok(e_tag)
            end
          end
        end

        Reader::SegmentTok.new(id, element_toks, nil, nil)
      end

      # @return [Reader::RepeatedElementTok]
      def repeated_tok(elements, element_use, designator)
        element_toks = []

        if element_use.composite?
          elements.each do |e_tag, e_val|
            unless e_tag == :composite or (e_tag.blank? and e_val.blank?)
              raise Exceptions::ParseError,
                "#{designator} is a composite element"
            end

            element_toks << composite_tok(e_val || [], element_use, designator)
          end
        else
          elements.each do |e_tag, e_val|
            unless e_val.nil?
              raise Exceptions::ParseError,
                "#{designator} is a simple element"
            end

            element_toks << simple_tok(e_tag)
          end
        end

        Reader::RepeatedElementTok.build(element_toks)
      end

      # @return [Reader::CompositeElementTok]
      def composite_tok(components, composite_use, designator)
        component_uses = composite_use.definition.component_uses

        if components.length > component_uses.length
          raise Exceptions::ParseError,
            "#{designator} has only #{component_uses.length} components"
        end

        component_idx  = "0"
        component_toks = []
        component_uses.zip(components) do |c_use, (c_tag, c_val)|
          component_idx.succ!

          unless c_val.nil?
            raise Exceptions::ParseError,
              "#{designator}-#{component_idx} is a component element"
          end

          component_toks << component_tok(c_tag)
        end

        Reader::CompositeElementTok.build(component_toks, nil, nil)
      end

      # @return [Reader::ComponentElementTok]
      def component_tok(value)
        Reader::ComponentElementTok.build(value, nil, nil)
      end

      # @return [Reader::SimpleElementTok]
      def simple_tok(value)
        Reader::SimpleElementTok.build(value, nil, nil)
      end

      # @endgroup
      #########################################################################

      # We can use a much faster implementation provided by the "called_from"
      # gem, but this only compiles against Ruby 1.8. Use this implementation
      # when its available, but fall back to the slow Kernel.caller method if
      # we have to
      if ::Kernel.respond_to?(:called_from)
        def caller(depth = 2)
          ::Kernel.called_from(depth)
        end
      else
        def caller(depth = 2)
          ::Kernel.caller.at(depth)
        end
      end

      private :caller
    end

    # @private
    class DslReader

      # @return [Reader::Separators]
      attr_reader :separators

      # @return [Reader::SegmentDict]
      attr_reader :segment_dict

      def initialize(separators, segment_dict)
        @separators, @segment_dict = separators, segment_dict
      end

      # @return [DslReader]
      def copy(changes = {})
        @separators   = changes.fetch(:separators, @separators)
        @segment_dict = changes.fetch(:segment_dict, @segment_dict)
        self
      end
    end

  end
end
