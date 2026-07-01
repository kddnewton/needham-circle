# frozen_string_literal: true

require "mail"
require "net/smtp"
require "openssl"

module NeedhamCircle
  # Sends transactional mail through the organizers' Gmail account over SMTP.
  # A personal @gmail.com account can't be driven by the service account we use
  # for Calendar (that needs Workspace domain-wide delegation), so this
  # authenticates with a Gmail app password instead — see SMTP_PASSWORD.
  class Mailer
    ADDRESS = "smtp.gmail.com"
    PORT = 587

    # SMTP and connection failures we translate into a friendly form error
    # rather than a 500, mirroring how GoogleCalendar::Result treats API errors.
    # Net::SMTPError is the mixin shared by every SMTP protocol error (auth,
    # busy, syntax, fatal); the rest are the ways the TCP/TLS connection itself
    # can fall over. Anything outside this set is a real bug and should surface.
    DELIVERY_ERRORS = [
      Net::SMTPError,
      Net::OpenTimeout,
      Net::ReadTimeout,
      IOError,
      SocketError,
      SystemCallError,
      OpenSSL::SSL::SSLError
    ].freeze

    class Result
      attr_reader :error #: Exception?

      #: (Exception? error) -> void
      def initialize(error)
        @error = error
      end

      #: () { () -> void } -> Result
      def self.wrap
        yield
        new(nil)
      rescue *DELIVERY_ERRORS => error
        new(error)
      end
    end

    #: (account: String, password: String) -> void
    def initialize(account:, password:)
      @account = account
      @password = password
    end

    # Delivers a contact-form submission to the organizers. The message is sent
    # from — and to — the organizers' own inbox with the visitor's address in
    # Reply-To, so hitting reply in Gmail goes straight back to them. Every piece
    # of the visitor's free text lives in the body, never in a header.
    #: (App::ContactForm form) -> Result
    def deliver_contact(form)
      Result.wrap do
        mail = Mail.new
        mail.from = @account
        mail.to = @account
        mail.reply_to = form.coerced_for(:email)
        mail.subject = subject_for(form)
        mail.body = body_for(form)
        mail.delivery_method(:smtp, smtp_settings)
        mail.deliver
      end
    end

    private

    #: () -> Hash[Symbol, untyped]
    def smtp_settings
      {
        address: ADDRESS,
        port: PORT,
        user_name: @account,
        password: @password,
        authentication: :login,
        enable_starttls_auto: true
      }
    end

    # Collapse any whitespace (including newlines) in the visitor's subject so it
    # can't smuggle extra headers, and fall back to a default when it's blank.
    #: (App::ContactForm form) -> String
    def subject_for(form)
      subject = form.coerced_for(:subject).gsub(/\s+/, " ").strip
      subject = "New contact message" if subject.empty?
      "[Needham Circle] #{subject}"
    end

    #: (App::ContactForm form) -> String
    def body_for(form)
      <<~BODY
        Name: #{form.coerced_for(:name)}
        Email: #{form.coerced_for(:email)}

        #{form.coerced_for(:message)}
      BODY
    end
  end
end
