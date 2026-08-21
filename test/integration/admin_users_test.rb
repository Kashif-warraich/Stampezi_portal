require "test_helper"

class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email: "boss@stampezi.it", password: "secret-one")
    post "/admin/login", params: { email: @admin.email, password: "secret-one" }
    follow_redirect!
  end

  test "the admin area is closed to anyone not signed in" do
    reset!
    get "/admin/users"
    assert_redirected_to "/admin/login?next=%2Fadmin%2Fusers"
  end

  test "creating an admin user stores a bcrypt digest, never the password" do
    assert_difference "User.count", 1 do
      post "/admin/users", params: { user: {
        email: "new@stampezi.it", password: "secret-two", password_confirmation: "secret-two"
      } }
    end

    created = User.find_by(email: "new@stampezi.it")
    assert created.authenticate("secret-two")
    assert_not created.authenticate("wrong")
    assert_not_equal "secret-two", created.password_digest
  end

  test "a blank password on update means unchanged, not blank" do
    patch "/admin/users/#{@admin.id}", params: { user: {
      email: "renamed@stampezi.it", password: "", password_confirmation: ""
    } }

    @admin.reload
    assert_equal "renamed@stampezi.it", @admin.email
    assert @admin.authenticate("secret-one"), "the original password must still work"
  end

  test "you cannot delete the account you are signed in as" do
    User.create!(email: "spare@stampezi.it", password: "secret-three")

    assert_no_difference "User.count" do
      delete "/admin/users/#{@admin.id}"
    end
    assert_redirected_to "/admin/users"
  end

  test "the last admin cannot be deleted" do
    other = User.create!(email: "only-other@stampezi.it", password: "secret-four")
    @admin.destroy!

    # Signed in as nobody now; sign in as the survivor and try to delete themselves away.
    post "/admin/login", params: { email: other.email, password: "secret-four" }
    assert_no_difference "User.count" do
      delete "/admin/users/#{other.id}"
    end
  end
end
