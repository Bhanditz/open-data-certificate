module CertificateFactory
  class Certificate

    def initialize(url, user_id, options = {})
      @url = url
      @user = User.find(user_id)
      @dataset_url = options[:dataset_url]
      @campaign = options[:campaign]
      @jurisdiction = options[:jurisdiction] || "gb"
      @create_user = options[:create_user] || true
      @existing_dataset = options[:existing_dataset]
    end

    def generate
      if existing_certificate?
        @campaign.increment!(:duplicate_count) if @campaign
      else
        generator = CertificateGenerator.transaction do
          CertificateGenerator.create(
            request: {
              documentationUrl: @url
            },
            user: @user,
            certification_campaign: @campaign)
        end
        CertificateGeneratorWorker.perform_async(generator.id, @jurisdiction, true, @existing_dataset.try(:id))
      end
    end

    def existing_certificate?
      @existing_dataset = Dataset.where(documentation_url: @url).first
      @existing_dataset.try(:certificate).present?
    end

  end
end
