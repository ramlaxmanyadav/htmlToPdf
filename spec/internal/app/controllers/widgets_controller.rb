class WidgetsController < ApplicationController
  around_action :html_to_pdf, only: [:show]

  # Declared after the around_action, matching the real-world ordering that
  # exposed the original gem's bug: anything this sets must still be visible
  # to the view when the request is being converted to a PDF.
  before_action :set_widget, only: [:show]

  cattr_accessor :show_invocations
  self.show_invocations = 0

  def index
    render plain: "widgets index"
  end

  def show
    self.class.show_invocations += 1
  end

  private

  def set_widget
    @widget = "Widget ##{params[:id]}"
  end
end
