require 'google_drive'

module UploadUsageData

  def self.perform
    [
      "published",
      "all"
    ].each do |type|
      certificates = Certificate.send(type)
      data = certificates.map do |cert|
        CertificatePresenter.new(cert).send("#{type}_data")
      end.compact
      unless data.empty?
        csv = create_csv(data)
        upload_csv(csv, "#{type.humanize} - #{Date.today.to_s}")
      end
    end

  ensure
    enqueue_next_run
  end

  def self.create_csv(data)
    csv = CSV.generate(force_quotes: true, row_sep: "\r\n") do |csv|
      # Header row goes here
      headers = data.first.keys
      csv << headers

      data.each {|c| csv << headers.map { |h| c[h] } }
    end
  end

  def self.find_collection(path)
    path = path.split("/")
    collection = session.collection_by_title(path.shift)
    path.each do |title|
      collection = collection.subcollections.select { |s| s.title == title }[0]
    end
    collection
  end

  def self.upload_csv(csv, title)
    file = session.upload_from_string(csv, title, content_type: "text/csv")
    collection = find_collection(ENV['GAPPS_CERTIFICATE_USAGE_COLLECTION'] || '')
    collection.add(file)
  end

  def self.session
    @@session ||= GoogleDrive.login(ENV['GAPPS_USER_EMAIL'], ENV['GAPPS_PASSWORD'])
  end

  def self.enqueue_next_run
    next_run_date = DateTime.now.utc.next_week
    # This is disgusting but Delayed::Job has no decent way to query outstanding jobs
    # We don't want to enqueue next weeks job more than once if it has to retry due to failures
    if Delayed::Job.where(["handler like ? and run_at > ?", "%#{name}%", DateTime.now.utc]).empty?
      Delayed::Job.enqueue UploadUsageData, { :priority => 5, :run_at => next_run_date }
    end
  end

end
