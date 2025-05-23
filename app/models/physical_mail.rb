class PhysicalMail < ApplicationRecord
  belongs_to :user

  scope :going_out, -> { where(status: :pending).or(where(status: :sent)) }

  enum :status, {
    pending: 0,
    sent: 1,
    failed: 2
  }

  enum :mission_type, {
    admin_mail: 0,
    first_time_7_streak: 1
  }

  scope :pending_delivery, -> {
    where(status: :pending)
      .joins(:user)
      .joins("INNER JOIN mailing_addresses ON mailing_addresses.user_id = users.id")
  }

  def link_to_theseus
    return nil if theseus_id.nil?

    "https://hack.club/#{theseus_id}"
  end

  def humanized_mission_type
    return "Your first 7-day streak" if first_time_7_streak?

    mission_type.titleize
  end

  def deliver!
    return if status == :sent || theseus_id.present?

    slug = "hackatime-#{mission_type.to_s.gsub("_", "-")}"

    flavors = FlavorText.compliment
    flavors.concat(FlavorText.rare_compliment) if rand(10) == 0

    return nil unless user.mailing_address.present?

    # authorization: Bearer <token>
    response = HTTP.auth("Bearer #{ENV["MAIL_HACKCLUB_TOKEN"]}").post("https://mail.hackclub.com/api/v1/letter_queues/#{slug}", json: {
      recipient_email: user.email_addresses.first.email,
      address: {
        first_name: user.mailing_address.first_name,
        last_name: user.mailing_address.last_name,
        line_1: user.mailing_address.line_1,
        line_2: user.mailing_address.line_2,
        city: user.mailing_address.city,
        state: user.mailing_address.state,
        postal_code: user.mailing_address.zip_code,
        country: user.mailing_address.country
      },
      rubber_stamps: flavors.sample,
      idempotency_key: "physical_mail_#{id}",
      metadata: {
        attributes: attributes
      }
    })

    if response.status.success?
      data = JSON.parse(response.body.to_s)
      puts "Successfully delivered physical mail: #{data["id"]}"
      update(status: :sent, theseus_id: data["id"])
    else
      update(status: :failed)
      raise "Failed to deliver physical mail: #{response.body}"
    end
  rescue => e
    update(status: :failed)
    raise e
  end

  private

  def user_address
    user.mailing_address
  end
end
