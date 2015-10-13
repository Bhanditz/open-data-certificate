# encoding: UTF-8
require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe QuestionGroup do
  let(:question_group){ FactoryGirl.create(:question_group) }
  let(:dependency){ FactoryGirl.create(:dependency) }
  let(:response_set){ FactoryGirl.create(:response_set) }

  context "when creating" do
    it { question_group.should be_valid }
    it "#display_type = inline by default" do
      question_group.display_type = "inline"
      question_group.renderer.should == :inline
    end
    it "#renderer == 'default' when #display_type = nil" do
      question_group.display_type = nil
      question_group.renderer.should == :default
    end
    it "interprets symbolizes #display_type to #renderer" do
      question_group.display_type = "foo"
      question_group.renderer.should == :foo
    end
    it "reports DOM ready #css_class based on dependencies" do
      question_group.dependency = dependency
      dependency.should_receive(:is_met?).and_return(true)
      question_group.css_class(response_set).should == "g_dependent"

      dependency.should_receive(:is_met?).and_return(false)
      question_group.css_class(response_set).should == "g_dependent g_hidden"

      question_group.custom_class = "foo bar"
      dependency.should_receive(:is_met?).and_return(false)
      question_group.css_class(response_set).should == "g_dependent g_hidden foo bar"
    end
    it "protects #api_id" do
      saved_attrs = question_group.attributes
      if defined? ActiveModel::MassAssignmentSecurity::Error
        expect { question_group.update_attributes(:api_id => "NEW") }.to raise_error(ActiveModel::MassAssignmentSecurity::Error)
      else
        question_group.attributes = {:api_id => "NEW"} # Rails doesn't return false, but this will be checked in the comparison to saved_attrs
      end
      question_group.attributes.should == saved_attrs
    end
    it "protects #created_at" do
      saved_attrs = question_group.attributes
      if defined? ActiveModel::MassAssignmentSecurity::Error
        expect { question_group.update_attributes(:created_at => 3.days.ago) }.to raise_error(ActiveModel::MassAssignmentSecurity::Error)
      else
        question_group.attributes = {:created_at => 3.days.ago} # Rails doesn't return false, but this will be checked in the comparison to saved_attrs
      end
      question_group.attributes.should == saved_attrs
    end
    it "protects #updated_at" do
      saved_attrs = question_group.attributes
      if defined? ActiveModel::MassAssignmentSecurity::Error
        expect { question_group.update_attributes(:updated_at => 3.hours.ago) }.to raise_error(ActiveModel::MassAssignmentSecurity::Error)
      else
        question_group.attributes = {:updated_at => 3.hours.ago} # Rails doesn't return false, but this will be checked in the comparison to saved_attrs
      end
      question_group.attributes.should == saved_attrs
    end
  end
end
