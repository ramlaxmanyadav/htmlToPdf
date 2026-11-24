class Document < ActiveRecord::Base
  has_one_attached :pdf
end
