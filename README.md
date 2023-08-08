# HtmlToPdf

Description : this gem will generate pdf of the action's html requested as pdf.

## Installation
#### Install and setup `wkhtmltopdf`. Please refer (link)[https://wkhtmltopdf.org/] 

Add this line to your application's Gemfile:

    gem 'htmlToPdf'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install htmlToPdf

## Usage

write following code inside Application Controller

    before_action :html_to_pdf

in views:

    <%= link_to 'download', your_action_path(:format => 'pdf') %>

customizing pdf downloads:

you can customize pdf like you can give the name and layout for the pdf.to customize pdf use this following example:

    <%= link_to 'download', your_action_path(:format => 'pdf',:pdf_options => {title: 'pdf_name', layout: 'layout_name'}) %>

 this will generate the pdf of your_action named "pdf_name.pdf" with layout "layout_name".

 one can call any action as pdf and he get the pdf file of that action's html.
