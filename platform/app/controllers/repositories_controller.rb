class RepositoriesController < ApplicationController
  before_action :require_login

  def index
    @pagy, @repositories = pagy(current_user.repositories.order(:full_name), limit: 20)
  end
end
