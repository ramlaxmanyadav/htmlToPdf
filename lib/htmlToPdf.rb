require "htmlToPdf/version"

module HtmlToPdf

  def html_to_pdf()
    pdf_options = params[:pdf_options] if params[:pdf_options]
    if request.format == 'application/pdf'
      initialize_downloads(pdf_options)
      FileUtils.mkdir_p(File.join(Rails.root, 'tmp'))
      _source_file = File.join(Rails.root, 'tmp', "#{Time.now.to_i.to_s}.html")
      _destination_file = File.join(Rails.root, 'tmp', "#{@name}.pdf")
      _html = render_to_string(:action => "#{action_name}", :formats => 'html', :layout => @layout )
      if  File.exists?('../public/assets')
        file_content = _html.gsub(/\/assets/, "../public/assets")
      else
        file_content = _html.gsub(/\/assets/, "../app/assets/stylesheets")
      end

      File.open(_source_file, "w+") do |f|
        f.write(file_content)
      end
      spec = Gem::Specification.find_by_name("htmlToPdf")
      gem_root = spec.gem_dir
      gem_lib = gem_root + "/bin"
      lib_path = "#{gem_lib}/wkhtmltopdf"

      `#{lib_path} #{_source_file} #{_destination_file}`
      #File.delete(_source_file) if File.exist?(_source_file)
      send_data File.open(_destination_file, "rb") { |f| f.read }, :disposition => 'attachment',:filename => "#{@name}.pdf"
      File.delete(_destination_file)
    end
  end

  def initialize_downloads(pdf_options)
    if pdf_options
      @name = pdf_options[:title].nil? ? "#{Time.now.to_i.to_s}" : pdf_options[:title]
      @layout = pdf_options[:layout].nil? ? 'application' : pdf_options[:layout]
    else
      @name = "#{Time.now.to_i.to_s}"
    end
  end

end

ActionController::Base.send(:include, HtmlToPdf)
