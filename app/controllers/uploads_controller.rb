# The customer-facing page reached by scanning a shop's QR code.
class UploadsController < ApplicationController
  LICENSE_COOKIE = :stampezi_shop
  # Long enough to pick a file and upload it, short enough that a borrowed phone forgets.
  LICENSE_COOKIE_MAX_AGE = 30.minutes

  def show
    license = params[:l]
    return if license.nil?

    # The QR encodes /upload?l=<licence>; swap it for an encrypted httpOnly cookie and
    # bounce to a clean /upload, so the phone's address bar shows no shop identity and
    # page JavaScript never sees the number either.
    if License.number?(license)
      cookies.encrypted[LICENSE_COOKIE] = {
        value: license,
        httponly: true,
        same_site: :lax,
        secure: Rails.env.production?,
        path: "/",
        expires: LICENSE_COOKIE_MAX_AGE.from_now
      }
    end

    redirect_to upload_path
  end
end
