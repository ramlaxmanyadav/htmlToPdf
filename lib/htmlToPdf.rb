require "htmlToPdf/version"

module HtmlToPdf

  def html_to_pdf()
    pdf_options = params[:pdf_options] ? params[:pdf_options] : {} 
    _pdf_options = ""
    if request.format == 'application/pdf'
      initialize_downloads(pdf_options)
      FileUtils.mkdir_p(File.join(Rails.root, 'tmp'))
      _source_file = File.join(Rails.root, 'tmp', "#{Time.now.to_i.to_s}.html")
      _destination_file = File.join(Rails.root, 'tmp', "#{@name}.pdf")
      _controller = ("#{controller_name}Controller").camelize.constantize.new
      _controller.method(action_name).call
      _assigns = {}
      _controller.instance_variables.each do |var|
        _assigns[var] = _controller.instance_variable_get(var)
      end
      _assigns.merge!({url: Rails.application.routes.url_helpers})
      
      _html = render_to_string(template: "#{controller_name}/#{action_name}", :layout => @layout, locals: _assigns)
      if  File.exist?('../public/assets')
        file_content = _html.gsub(/\/assets/, "../public/assets")
      else
        file_content = _html.gsub(/\/assets/, "../app/assets/stylesheets")
      end
      file_content = _html.gsub(/\\&quot;/, "")


      File.open(_source_file, "w+") do |f|
        f.write(file_content)
      end
      pdf_options.delete(:title)
      pdf_options.delete(:layout)
      # _pdf_options = pdf_options.each {|key, value| _pdf_options+"--#{key.to_s} #{value} "}
      system("wkhtmltopdf #{_source_file} #{_destination_file}")
      File.delete(_source_file) if File.exist?(_source_file)
      send_data File.open(_destination_file, "rb") { |f| f.read }, :disposition => 'attachment',:filename => "#{@name}.pdf"
      File.delete(_destination_file)
    end
  end

  def initialize_downloads(pdf_options = {})
    if pdf_options
      @name = pdf_options[:title].nil? ? "#{Time.now.to_i.to_s}" : pdf_options[:title]
      @layout = pdf_options[:layout].nil? ? 'application' : pdf_options[:layout]
    else
      @name = "#{Time.now.to_i.to_s}"
      @layout = 'application'
    end
  end

end

ActionController::Base.send(:include, HtmlToPdf)
