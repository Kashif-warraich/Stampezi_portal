ActiveAdmin.register User do
  menu priority: 90, label: "Admin users"

  # password_digest never goes near a form or a page; the password fields below write
  # through has_secure_password, which hashes on assignment.
  permit_params :email, :password, :password_confirmation

  index do
    selectable_column
    column :email
    column :created_at
    actions
  end

  filter :email
  filter :created_at

  show do
    attributes_table do
      row :email
      row :created_at
      row :updated_at
    end
  end

  form do |f|
    f.inputs do
      f.input :email
      f.input :password, hint: f.object.persisted? ? "Leave blank to keep the current password" : nil
      f.input :password_confirmation
    end
    f.actions
  end

  controller do
    # Blank password on an update means "unchanged", not "set it to empty".
    def update
      if params[:user][:password].blank?
        params[:user].delete(:password)
        params[:user].delete(:password_confirmation)
      end
      super
    end

    # Locking yourself out of the only admin account is not a recoverable mistake.
    def destroy
      if resource == current_user
        redirect_to admin_users_path, alert: "You cannot delete the account you are signed in as."
      elsif User.count <= 1
        redirect_to admin_users_path, alert: "There must be at least one admin user."
      else
        super
      end
    end
  end
end
