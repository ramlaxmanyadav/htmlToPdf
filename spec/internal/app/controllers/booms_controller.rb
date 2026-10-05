class BoomsController < ApplicationController
  class Boom < StandardError; end

  around_action :html_to_pdf, only: [:show]
  rescue_from Boom, with: :handle_boom

  def show
    raise Boom, "deliberate failure for spec coverage"
  end

  private

  def handle_boom
    render plain: "handled", status: :unprocessable_content
  end
end
