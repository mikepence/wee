require 'wee/abstractsession'

class Wee::Session < Wee::AbstractSession

  attr_accessor :root_component
  attr_accessor :page_store

  def initialize(&block)
    super()
    setup(&block)
  end

  def current_callbacks
    @page.callbacks
  end

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # :section: Request processing/handling
  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  protected

  def setup(&block)
    @idgen = Wee::SimpleIdGenerator.new

    with_session do
      block.call(self) if block
      raise ArgumentError, "No root component specified" if @root_component.nil?
      raise ArgumentError, "No page_store specified" if @page_store.nil?
    
      @initial_snapshot = snapshot()
    end
  end

  # The main routine where the request is processed.

  def process_request
    if @context.request.page_id.nil?

      # No page_id was specified in the URL. This means that we start with a
      # fresh component and a fresh page_id, then redirect to render itself.

      handle_new_page

    elsif @page = @page_store.fetch(@context.request.page_id, false)

      # A valid page_id was specified and the corresponding page exists.

      handle_existing_page

    else

      # A page_id was specified in the URL, but there's no page for it in the
      # page store. Either the page has timed out, or an invalid page_id was
      # specified. 

      handle_invalid_page

    end
  end

  def handle_new_page
    handle_new_page_view(@context, @initial_snapshot)
  end

  def handle_existing_page
    @page.snapshot.restore if @context.request.page_id != @snapshot_page_id 

    p @context.request.fields if $DEBUG

    if @context.request.render?
      handle_render_phase
    else
      handle_callback_phase
    end
  end

  def handle_invalid_page
    # TODO:: Display an "invalid page or page timed out" message, which
    # forwards to /app/session-id
    raise "Not yet implemented"
  end

  def handle_render_phase
    # No action/inputs were specified -> render page
    #
    # 1. Reset the action/input fields (as they are regenerated in the
    #    rendering process).
    # 2. Render the page (respond).
    # 3. Store the page back into the store

    @page = create_page(@page.snapshot)  # remove all action/input handlers
    respond(@context, @page.callbacks)                    # render
    @page_store[@context.request.page_id] = @page         # store
  end

  def handle_callback_phase
    # Actions/inputs were specified.
    #
    # We process the request and invoke actions/inputs. Then we generate a
    # new page view. 

    callback_stream = Wee::CallbackStream.new(@page.callbacks, @context.request.fields) 
    premature_response = process_callbacks(callback_stream)

    post_callbacks_hook()

    if premature_response
      # replace existing page with new snapshot
      @page.snapshot = self.snapshot
      @page_store[@context.request.page_id] = @page
      @snapshot_page_id = @context.request.page_id  

      # and send response
      set_response(@context, send_response) 
    else
      handle_new_page_view(@context)
    end
  end

  # Values are parameters to method #process_callbacks_of

  DEFAULT_CALLBACK_PROCESSING = [
    # Invokes all specified input callbacks. NOTE: Input callbacks should never
    # call other components!
    [:input, callback_stream, true, false],

    # Invokes the first found action callback. NOTE: Only the first action
    # callback is invoked. Any other action callback is ignored.
    [:action, callback_stream, false, true],
    
    # Invoke live_update callback (NOTE: only the first is invoked).
    [:live_update, callback_stream, false, true]
  ]

  # This method triggers several tree traversals to process the callbacks of
  # the root component.
  #
  # Returns nil or a Response object in case of a premature response.

  def process_callbacks(callback_stream)
    if callback_stream.all_of_type(:action).size > 1 
      raise "Not allowed to specify more than one action callback"
    end

    catch(:wee_abort_callback_processing) { 
      DEFAULT_CALLBACK_PROCESSING.each {|args| process_callbacks_of(*args) }
      nil
    }
  end

  def process_callbacks_of(type, callback_stream, pass_value=true, once=false)
    @root_component.process_callbacks_chain {|this|
      callback_stream.with_callbacks_for(this, type) { |callback, value|
        if pass_value
          callback.call(value)
        else
          callback.call
        end
        return if once
      }
    }
  end

  def handle_new_page_view(context, snapshot=nil)
    new_page_id = @idgen.next.to_s
    new_page = create_page(snapshot || self.snapshot())
    @page_store[new_page_id] = new_page
    @snapshot_page_id = new_page_id 
    redirect_url = context.request.build_url(:page_id => new_page_id)
    set_response(context, Wee::RedirectResponse.new(redirect_url))
  end

  def respond(context, callbacks)
    pre_respond_hook
    set_response(context, Wee::GenericResponse.new('text/html', ''))

    rctx = Wee::RenderingContext.new(context.request, context.response, callbacks, Wee::HtmlWriter.new(context.response.content))
    @root_component.do_render_chain(rctx)
  end

  def pre_respond_hook
  end

  def post_callbacks_hook
  end

  # Take a snapshot of the root component and return it.

  def snapshot
    @root_component.backtrack_state_chain(snap = Wee::Snapshot.new)
    return snap.freeze
  end

  # Return a new Wee::Page object with the given snapshot assigned.

  def create_page(snapshot)
    idgen = Wee::SimpleIdGenerator.new
    page = Wee::Page.new(snapshot, Wee::CallbackRegistry.new(idgen))
  end

end
