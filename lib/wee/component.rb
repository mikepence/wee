require 'wee/presenter'
require 'wee/decoration'
require 'wee/call_answer'

module Wee

  #
  # The base class of all components. You should at least overwrite method
  # #render in your own subclasses.
  #
  class Component < Presenter

    #
    # Constructs a new instance of the component.
    #
    # Overwrite this method when you want to use it both as a root component
    # and as a non-root component. Here you can add neccessary decorations
    # when used as root component, as for example a PageDecoration or a
    # FormDecoration. 
    #
    # By default this methods adds no decoration.
    #
    # See also class RootComponent.
    #
    def self.instanciate(*args, &block)
      new(*args, &block)
    end

    #
    # Initializes a newly created component.
    #
    def initialize
    end

    #
    # This method renders the content of the component.
    #
    # *OVERWRITE* this method in your own component classes to implement the
    # view. By default this method does nothing!
    #
    # [+r+]
    #    An instance of class <tt>renderer_class()</tt>
    #
    def render(r)
    end

    #
    # Take snapshots of objects that should correctly be backtracked.
    #
    # Backtracking means that you can go back in time of the components' state.
    # Therefore it is neccessary to take snapshots of those objects that want to
    # participate in backtracking. Taking snapshots of the whole component tree
    # would be too expensive and unflexible. Note that methods
    # <i>take_snapshot</i> and <i>restore_snapshot</i> are called for those
    # objects to take the snapshot (they behave like <i>marshal_dump</i> and
    # <i>marshal_load</i>). Overwrite them if you want to define special
    # behaviour. 
    #
    # By default only the decoration chain is backtracked. This is
    # required to correctly backtrack called components. To disable
    # backtracking of the decorations, change method
    # Component#state_decoration to a no-operation:
    #
    #   def state_decoration(s)
    #     # nothing here
    #   end
    #
    # [+s+]
    #    An object of class State
    #
    def state(s)
      state_decoration(s)
      for child in self.children
        child.decoration.state(s)
      end
    end

    NO_CHILDREN = [].freeze
    #
    # Return all child components.
    #
    # *OVERWRITE* this method and return all child components
    # collected in an array.
    #
    def children
      return NO_CHILDREN
    end

    #
    # Process and invoke all input callbacks specified for this component 
    # and all of it's child components.
    #
    # Returns the action callback to be invoked.
    #
    def process_callbacks(callbacks)
      callbacks.input_callbacks.each_triggered_call_with_value(self)

      action_callback = nil

      # process callbacks of all children
      for child in self.children
        if act = child.decoration.process_callbacks(callbacks)
          raise "Duplicate action callback" if action_callback
          action_callback = act
        end
      end

      if act = callbacks.action_callbacks.first_triggered(self)
        raise "Duplicate action callback" if action_callback
        action_callback = act
      end

      return action_callback
    end

    protected

    def state_decoration(s)
      s.add_ivar(self, :@decoration, @decoration)
    end

    include Wee::DecorationMixin
    include Wee::CallAnswerMixin

  end # class Component

  #
  # A RootComponent has a special instanciate class method that
  # makes it more comfortable for root components.
  #
  class RootComponent < Component
    def title
      self.class.name.to_s
    end
    def stylesheets; [] end
    def javascripts; [] end

    def self.instanciate(*args, &block)
      obj = new(*args, &block)
      unless obj.find_decoration {|d| d.kind_of?(Wee::FormDecoration)}
        obj.add_decoration Wee::FormDecoration.new
      end
      unless obj.find_decoration {|d| d.kind_of?(Wee::PageDecoration)}
        obj.add_decoration Wee::PageDecoration.new(obj.title, obj.stylesheets, obj.javascripts)
      end
    end
  end # class RootComponent

end # module Wee
