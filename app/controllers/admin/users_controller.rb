module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[edit update destroy]

    def index
      @users = User.order(:email)
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(user_params)
      if @user.save
        redirect_to admin_users_path, notice: "Admin user created"
      else
        flash.now[:alert] = @user.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      # Blank password on an update means "unchanged", not "set it to empty".
      attrs = user_params
      attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?

      if @user.update(attrs)
        redirect_to admin_users_path, notice: "Admin user updated"
      else
        flash.now[:alert] = @user.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # Locking yourself out of the only admin account is not a recoverable mistake.
    def destroy
      if @user == current_user
        redirect_to admin_users_path, alert: "You cannot delete the account you are signed in as."
      elsif User.count <= 1
        redirect_to admin_users_path, alert: "There must be at least one admin user."
      else
        @user.destroy!
        redirect_to admin_users_path, notice: "Deleted #{@user.email}"
      end
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    # password_digest never goes near a form or a page; the password fields write through
    # has_secure_password, which hashes on assignment.
    def user_params
      params.require(:user).permit(:email, :password, :password_confirmation)
    end
  end
end
