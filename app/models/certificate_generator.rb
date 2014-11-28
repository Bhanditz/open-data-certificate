class CertificateGenerator < ActiveRecord::Base

  belongs_to :user
  belongs_to :response_set
  belongs_to :certification_campaign

  has_one :dataset, through: :response_set
  has_one :certificate, through: :response_set
  has_one :survey, through: :response_set

  serialize :request, HashWithIndifferentAccess

  TYPES =  {
    none: 'string',
    one: 'radio',
    any: 'checkbox',
    repeater: 'repeating'
  }

  def self.schema(request)
    survey = Survey.newest_survey_for_access_code request['jurisdiction']
    return {errors: ['Jurisdiction not found']} if !survey

    schema = {}
    survey.questions.each do |q|
      next if q.display_type == 'label'
      schema[q.reference_identifier] = question = {question: q.text, type: TYPES[q.type], required: q.is_mandatory}

      if q.type == :one || q.type == :any
        question['options'] = {}
        q.answers.each{|a| question['options'][a.reference_identifier] = a.text }
      end

      question
    end

    {schema: schema}
  end

  # attempt to build a certificate from the request
  def self.update(dataset, request, jurisdiction, user)

    # Finds a migrated survey if there is one
    survey = Survey.newest_survey_for_access_code Survey::migrate_access_code(jurisdiction)
    return {success: false, errors: ['Jurisdiction not found']} if !survey

    if user.admin?
      response_set = ResponseSet.where(dataset_id: dataset).latest
    else
      response_set = ResponseSet.where(dataset_id: dataset, user_id: user).latest
    end
    return {success: false, errors: ['Dataset not found']} if !response_set

    if survey != response_set.survey || !response_set.modifications_allowed?
      response_set = ResponseSet.clone_response_set(response_set, {survey_id: survey.id, user_id: user.id, dataset_id: response_set.dataset_id})
    end

    generator = response_set.certificate_generator || self.create(response_set: response_set, user: user)
    generator.request = request
    certificate = generator.generate(jurisdiction, false)
    response_set = certificate.response_set

    errors = []

    response_set.responses_with_url_type.each do |response|
      if response.error
        errors.push("The question '#{response.question.reference_identifier}' must have a valid URL")
      end
    end

    survey.questions.where(is_mandatory: true).each do |question|
      response = response_set.responses.detect {|r| r.question_id == question.id}

      if !response || response.empty?
        errors.push("The question '#{question.reference_identifier}' is mandatory")
      end
    end

    {success: true, published: response_set.published?, errors: errors}
  end

  def generate(jurisdiction, create_user, dataset = nil)
    build_response_set(survey: Survey.newest_survey_for_access_code(jurisdiction))
    # mass assignment protection avoidance
    response_set.dataset = dataset if dataset
    save!

    # find the questions which are to be answered
    survey.questions
          .where({reference_identifier: request.keys})
          .includes(:answers)
          .each {|question| answer question}

    response_set.autocomplete(request["documentationUrl"])

    if response_set.kitten_data && create_user
      email = response_set.kitten_data[:data][:publishers].first.mbox.presence rescue nil
      if email
        new_user = User.find_or_create_by_email(email) do |user|
          user.password = SecureRandom.base64
        end
      end
    end

    user = new_user.try(:persisted?) ? new_user : self.user
    response_set.assign_to_user!(user)

    response_set.reload
    mandatory_complete = response_set.all_mandatory_questions_complete?
    urls_resolve = response_set.all_urls_resolve?

    if mandatory_complete && urls_resolve
      response_set.complete!
      response_set.publish!
    end

    self.completed = true
    save!

    certificate
  end

  def published?
    certificate.try(:published?)
  end

  def dataset_url
    dataset.api_url
  end

  # the dataset parameters from the request, defaults to {}
  def request=(value)
    write_attribute(:request, value.with_indifferent_access)
  end

  private
  # answer a question from the request
  def answer question

    # find the value that should be entered
    data = request[question[:reference_identifier]]

    response_set.responses.where(question_id: question).delete_all

    case question.type

    when :none
      answer = question.answers.first
      response_set.responses.create({
        answer: answer,
        question: question,
        string_value: data
      })

    when :one
      # the value is the reference identifier of the target answer
      answer = question.answers.where(reference_identifier: data).first

      unless answer.nil?
        response_set.responses.create({
          answer: answer,
          question: question
        })
      end

    when :any
      # the value is an array of the chosen answers
      answers = question.answers.where(reference_identifier: data)
      answers.each do |answer|
        response_set.responses.create({
          answer: answer,
          question: question
        })
      end

    when :repeater
      # the value is an array of answers
      answer = question.answers.first
      i = 0
      data.each do |value|
        response_set.responses.create({
          answer: answer,
          question: question,
          string_value: value,
          response_group: i
        })
        i += 1
      end

    else
      throw "not handled> #{question.inspect}"
    end

  end

end
