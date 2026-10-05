# frozen_string_literal: true

Rails.application.routes.draw do
  resources :widgets, only: [:index, :show]
  resources :booms, only: [:show]
end
