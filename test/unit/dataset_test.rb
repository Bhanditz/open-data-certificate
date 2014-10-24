require 'test_helper'

class DatasetTest < ActiveSupport::TestCase

  [
    [:untitled_dataset, :title, :set_default_title!, "Test original title", "Test dataset default title"],
    [:dataset, :curator, :set_default_curator!, "Some Org", "Newer Org"],
    [:dataset_without_documentation_url, :documentation_url, :set_default_documentation_url!, "http://original.org", "http://new.org"]
  ].each do |factory, attr, method, orig_value, new_value|
    test "sets the #{attr} if it hasn't been set before" do
      dataset = FactoryGirl.create(factory)
      dataset.send(method, new_value)
      dataset.reload

      assert_equal(dataset.send(attr), new_value)
    end

    test "overwrites the #{attr} if it has been set before" do
      dataset = FactoryGirl.create(factory, attr => orig_value)
      assert_equal(dataset.send(attr), orig_value)
      dataset.reload

      dataset.send(method, new_value)
      dataset.reload

      assert_equal(dataset.send(attr), new_value)
    end
  end

  test "#newest_response_set should return the most recent response set" do

    dataset = FactoryGirl.create(:dataset, documentation_url: 'http://foo.com')
    survey = FactoryGirl.create(:survey)
    response_set_1 = FactoryGirl.create(:response_set, survey: survey, dataset: dataset)
    response_set_2 = FactoryGirl.create(:response_set, survey: survey, dataset: dataset)

    dataset.reload

    assert_equal(dataset.newest_response_set, response_set_2)
  end

  test "#newest_completed_response_set should return the most recent response set completed" do
    dataset = FactoryGirl.create(:dataset, documentation_url: 'http://foo.com')
    survey = FactoryGirl.create(:survey)
    response_set_1 = FactoryGirl.create(:response_set, survey: survey, dataset: dataset)
    completed_response_set_2 = FactoryGirl.create(:completed_response_set, survey: survey, dataset: dataset)
    completed_response_set_3 = FactoryGirl.create(:completed_response_set, survey: survey, dataset: dataset)
    response_set_4 = FactoryGirl.create(:response_set, survey: survey, dataset: dataset)

    dataset.reload

    assert_equal(dataset.newest_completed_response_set, completed_response_set_3)
  end

  test "#destroy_if_no_responses should not destroy the dataset if the response_sets is not empty" do

    dataset = FactoryGirl.create(:dataset, documentation_url: 'http://foo.com')
    response_set = FactoryGirl.create(:response_set, dataset: dataset)
    dataset.reload

    dataset.destroy_if_no_responses

    dataset = Dataset.find_by_id(dataset.id)

    refute_nil(dataset)
  end

  test "#destroy_if_no_responses should destroy the dataset if the response_sets is empty"  do

    dataset = FactoryGirl.create(:dataset, documentation_url: 'http://foo.com')

    dataset.reload

    dataset.destroy_if_no_responses
    dataset = Dataset.find_by_id(dataset.id)
    assert_nil(dataset)
  end

  test "#response_set should give the published dataset" do

    dataset = FactoryGirl.create(:dataset)

    FactoryGirl.create_list(:response_set, 10, dataset: dataset)

    active = dataset.response_sets[5]
    active.publish!

    assert_equal active, dataset.response_set
  end

  test "#certificate should give the published certificate" do

    dataset = FactoryGirl.create(:dataset)

    FactoryGirl.create_list(:response_set, 10, dataset: dataset)

    active = dataset.response_sets[5]
    active.publish!

    assert_equal active.certificate, dataset.certificate
  end

  test "removed is false by default and not mass-assignable" do
    dataset = FactoryGirl.create(:dataset)
    dataset.update_attributes({removed: true})

    refute dataset.removed
  end

  test 'creates an embed stat' do
    dataset = FactoryGirl.create(:dataset)
    dataset.register_embed("http://example.com/page")

    assert_equal 1, EmbedStat.all.count
    assert_equal dataset, EmbedStat.first.dataset
  end

  test 'creates one embed stat per URL through dataset' do
    2.times do |i|
      dataset = FactoryGirl.create(:dataset)
      5.times { dataset.register_embed("http://example.com/page") }
    end

    assert_equal 2, EmbedStat.all.count
  end

  test 'get results of autopublished certificate' do
    load_custom_survey 'cert_generator.rb'
    user = FactoryGirl.create :user
    survey = Survey.newest_survey_for_access_code 'cert-generator'

    request = {
      jurisdiction: 'cert-generator',
      dataset: {
        dataTitle: 'The title',
        releaseType: 'oneoff',
        publisherUrl: 'http://www.example.com',
        publisherRights: 'yes',
        publisherOrigin: 'true',
        linkedTo: 'true',
        chooseAny: ['one', 'two']
      }
    }

    CertificateGenerator.create(request: request, survey: survey, user: user).generate(false)
    response = Dataset.last.generation_result

    assert_equal(true, response[:success])
    assert_equal(true, response[:published])
    assert_equal(user.email, response[:owner_email])
    assert_equal([], response[:errors])
  end

  test 'get results of certificate with missing field' do
    load_custom_survey 'cert_generator.rb'
    user = FactoryGirl.create :user
    survey = Survey.newest_survey_for_access_code 'cert-generator'

    request = {
      jurisdiction: 'cert-generator',
      dataset: {
        releaseType: 'oneoff',
        publisherUrl: 'http://www.example.com',
        publisherRights: 'yes',
        publisherOrigin: 'true',
        linkedTo: 'true',
        chooseAny: ['one', 'two']
      }
    }

    CertificateGenerator.create(request: request, survey: survey, user: user).generate(false)
    response = Dataset.last.generation_result

    assert_equal(true, response[:success])
    assert_equal(false, response[:published])
    assert_equal(["The question 'dataTitle' is mandatory"], response[:errors])
  end

  test 'get results of certificate with invalid URL' do
    load_custom_survey 'cert_generator.rb'
    user = FactoryGirl.create :user
    survey = Survey.newest_survey_for_access_code 'cert-generator'

    stub_request(:get, "http://www.example/error").
        to_return(:body => "", status: 404)

    request = {
      jurisdiction: 'cert-generator',
      dataset: {
        dataTitle: 'The title',
        releaseType: 'oneoff',
        publisherUrl: 'http://www.example/error',
        publisherRights: 'yes',
        publisherOrigin: 'true',
        linkedTo: 'true',
        chooseAny: ['one', 'two']
      }
    }

    CertificateGenerator.create(request: request, survey: survey, user: user).generate(false)
    response = Dataset.last.generation_result

    assert_equal(true, response[:success])
    assert_equal(false, response[:published])
    assert_equal(["The question 'publisherUrl' must have a valid URL"], response[:errors])
  end

  test 'doesn\'t show results when generation hasn\'t happened' do
    load_custom_survey 'cert_generator.rb'
    user = FactoryGirl.create :user
    survey = Survey.newest_survey_for_access_code 'cert-generator'

    request = {
      jurisdiction: 'cert-generator',
      dataset: {
        dataTitle: 'The title',
        releaseType: 'oneoff',
        publisherUrl: 'http://www.example.com',
        publisherRights: 'yes',
        publisherOrigin: 'true',
        linkedTo: 'true',
        chooseAny: ['one', 'two']
      }
    }

    cert = CertificateGenerator.create(request: request, survey: survey, user: user)
    response = Dataset.last.generation_result

    assert_equal("pending", response[:success])
    assert_equal("http://test.dev/datasets/#{Dataset.last.id}.json", response[:dataset_url])

    cert.generate(false)
    response = Dataset.last.generation_result

    assert_equal(true, response[:success])
    assert_equal(true, response[:published])
    assert_equal(user.email, response[:owner_email])
    assert_equal([], response[:errors])
  end

  test 'returns an api_url' do
    dataset = FactoryGirl.create(:dataset)

    assert_equal "http://test.dev/datasets/1.json", dataset.api_url
  end

end
