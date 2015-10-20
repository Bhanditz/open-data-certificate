class SurveyorController < ApplicationController
  unloadable
  include Surveyor::SurveyorControllerMethods

  before_filter :set_response_set_and_render_context
  before_filter :ensure_modifications_allowed, only: [:edit, :update]


  layout 'application'

  # this is now in the application_controller
  def create
    params[:survey_access_code] = params[:survey_code]
    start_questionnaire
  end

  # it might be a *really* nice refactor to take this to response_set_controller#update
  # then we could use things like `form_for [surveyor, response_set] do |f|`
  def continue
    if Survey::MIGRATIONS.has_key? params[:survey_code]
      # lets switch over to the new questionnaire
      nxt = Survey::MIGRATIONS[params[:survey_code]]

      survey = Survey.newest_survey_for_access_code nxt

      unless survey.nil?
        switch_survey(survey)
      end

    elsif params[:juristiction_access_code]
      # they *actually* want to swap the jurisdiction

      survey = Survey.newest_survey_for_access_code(params[:juristiction_access_code])
      unless survey.nil?
        switch_survey(survey)

        # the user has made a concious effort to switch jurisdictions, so set it as their default
        if user_signed_in?
          current_user.update_attributes default_jurisdiction: params[:juristiction_access_code]
        end
      end

    elsif @response_set.survey.superseded?
      latest_survey = Survey.newest_survey_for_access_code(params[:survey_code])
      unless latest_survey.nil?
        switch_survey(latest_survey)
      end
    elsif !@response_set.modifications_allowed?
      # they *actually* want to create a new response set
      attrs = prepare_new_response_set
      create_new_response_set(attrs)
    end

    redirect_options = {
      survey_code: @response_set.survey.access_code,
      response_set_code: @response_set.access_code
    }
    redirect_options[:anchor] = "q_#{params[:question]}" if params[:question]
    if params[:update]
      redirect_options[:update] = true
      flash[:warning] = t('response_set.update_instructions')
    end

    redirect_to surveyor.edit_my_survey_path(redirect_options)
  end

  def update
    if @response_set

      if @response_set.published?
        return redirect_with_message(surveyor_index, :warning, t('surveyor.response_set_is_published'))
      end

      saved = load_and_update_response_set_with_retries

      if saved && !request.xhr?
        flash[:_saved_response_set] = @response_set.access_code

        if user_signed_in?
          mandatory_questions_complete = @response_set.all_mandatory_questions_complete?
          urls_resolve = @response_set.all_urls_resolve?

          unless mandatory_questions_complete
            flash[:alert] = t('surveyor.all_mandatory_questions_need_to_be_completed')
          end

          unless urls_resolve
            flash[:warning] = t('surveyor.please_check_all_your_urls_exist')
          end

          if mandatory_questions_complete && urls_resolve
            @response_set.complete!
            @response_set.save

            if params[:update]
              @response_set.publish!
              return redirect_to(dashboard_path, notice: t('dashboard.updated_response_set'))
            else
              return redirect_with_message(surveyor_finish, :notice, t('surveyor.completed_survey'))
            end
          end
        else
          flash[:alert] = t('surveyor.must_be_logged_in_to_complete')
        end

        return redirect_to(surveyor.edit_my_survey_path({
          :anchor => anchor_from(params[:section]),
          :section => section_id_from(params),
          :highlight_mandatory => true,
          :update => params[:update]
        }.reject! {|k, v| v.nil? }))
      end
    end

    respond_to do |format|
      format.html do
        if @response_set
          flash[:warning] = t('surveyor.unable_to_update_survey') unless saved
          redirect_to surveyor.edit_my_survey_path(:anchor => anchor_from(params[:section]), :section => section_id_from(params))
        else
          redirect_with_message(surveyor.available_surveys_path, :notice, t('surveyor.unable_to_find_your_responses'))
        end
      end
      format.js do
        if @response_set
          question_ids_for_dependencies = (params[:r] || []).map { |k, v| v["question_id"] }.compact.uniq
          render :json => @response_set.reload.all_dependencies(question_ids_for_dependencies)
        else
          render :text => "No response set #{params[:response_set_code]}", :status => 404
        end
      end
    end
  end

  def repeater_field
    @responses = @response_set.responses.includes(:question).all
    question = Question.find(params[:question_id])
    @rc = params[:response_index].to_i
    render :partial => "partials/repeater_field", locals: {response_group: params[:response_group] || 0, question: question}
  end

  def requirements
    if @response_set
      redirect_to improvements_dataset_certificate_path(@response_set.dataset, @response_set.certificate)
    else
      flash[:warning] = t('surveyor.unable_to_find_your_responses')
      redirect_to surveyor_index
    end
  end

  def edit
    # @response_set is set in before_filter - set_response_set_and_render_context
    if @response_set
      @responses = @response_set.responses.includes(:question).all
      @survey = @response_set.survey
      @sections = @survey.sections.with_includes
      @dependents = []
      @update = true if params[:update]
    else
      flash[:notice] = t('surveyor.unable_to_find_your_responses')
      redirect_to surveyor_index
    end
  end

  def start
    # this is an alternate view of the edit functionality,
    # with only the documentation url displayed
    edit
    @url_error = @response_set.documentation_url_explanation.present?
  end

  # where to send the user once the survey has been completed
  # if there was a dataset, go back to it
  private
  def surveyor_finish
    dashboard_path
  end

  def ensure_modifications_allowed
    unless @response_set.modifications_allowed?
      flash[:warning] = t('surveyor.modifications_not_allowed')
      redirect_to dashboard_path
    end
  end

  def set_response_set_and_render_context
    super
    raise ActiveRecord::RecordNotFound unless @response_set.present?
    authorize!(:edit, @response_set)
  end

  def prepare_new_response_set
    keep = %w[survey_id user_id dataset_id]
    @response_set.attributes.slice(*keep)
  end

  def create_new_response_set(attrs)
    @response_set = ResponseSet.clone_response_set(@response_set, attrs)
  end

  def switch_survey(survey)
    attrs = prepare_new_response_set
    attrs['survey_id'] = survey.id
    response_set = @response_set
    create_new_response_set(attrs)
    response_set.supersede! if response_set.draft?
  end

end
