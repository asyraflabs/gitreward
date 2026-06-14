class WalletsController < ApplicationController
  before_action :require_login

  def show
    @wallet = current_user.active_wallet || current_user.wallet_links.build
  end

  # Link (or replace) the user's active payout wallet. The address the user
  # enters here IS their explicit confirmation of where to be paid (A.1 #4) —
  # a bad address is their assertion, not platform liability (§3.4).
  def create
    # Create inactive, then activate! (which deactivates the prior active wallet
    # in one transaction). Building it active would collide with the existing
    # active wallet under the one-active-per-user unique index.
    wallet = current_user.wallet_links.build(address: wallet_params[:address], active: false)
    if wallet.save
      wallet.activate!
      redirect_to dashboard_path, notice: "Payout wallet linked: #{wallet.address}"
    else
      @wallet = wallet
      flash.now[:alert] = wallet.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  private

  def wallet_params
    params.require(:wallet_link).permit(:address)
  end
end
