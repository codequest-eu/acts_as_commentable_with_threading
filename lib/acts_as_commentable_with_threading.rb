require 'active_record'
require 'awesome_nested_set'
ActiveRecord::Base.class_eval do
  include CollectiveIdea::Acts::NestedSet
end

unless ActiveRecord::Base.respond_to?(:acts_as_nested_set)
  ActiveRecord::Base.send(:include, CollectiveIdea::Acts::NestedSet::Base)
end

# ActsAsCommentableWithThreading
module Acts #:nodoc:
  module CommentableWithThreading #:nodoc:
    extend ActiveSupport::Concern

    module ClassMethods

      def acts_as_commentable(*args)
        comment_roles = args.to_a.flatten.compact.map(&:to_sym)

        class_attribute :comment_types
        self.comment_types = (comment_roles.blank? ? [:comments] : comment_roles)

        options = ((args.blank? or args[0].blank?) ? {} : args[0])

        if !comment_roles.blank?
          comment_roles.each do |role|

            has_many "#{role.to_s}_comment_threads".to_sym,
                     {:class_name => "Comment",
                      :as => :commentable,
                      :dependent => :destroy,
                      :conditions => ["role = ?", role.to_s],
                      :before_add => Proc.new { |x, c| c.role = role.to_s }}

            before_destroy { |record| record.send("root_#{role.to_s}_comments").destroy_all }

          end
        else
          has_many :comment_threads, :class_name => "Comment", :as => :commentable
          before_destroy { |record| record.root_comments.destroy_all }
        end

        comment_types.each do |role|
          method_name = (role == :comments ? "comments" : "#{role.to_s}_comments").to_s
          class_eval %{

              def self.find_#{method_name}_for(obj)
                commentable = self.base_class.name
                Comment.find_comments_for_commentable(commentable, obj.id, "#{role.to_s}")
              end

              def self.find_#{method_name}_by_user(user)
                commentable = self.base_class.name
                Comment.where(["user_id = ? and commentable_type = ? and role = ?", user.id, commentable, "#{role.to_s}"]).order("created_at DESC")
              end

              def #{method_name}_ordered_by_submitted
                Comment.find_comments_for_commentable(self.class.name, id, "#{role.to_s}")
              end

              def add_#{method_name.singularize}(comment)
                comment.role = "#{role.to_s}"
                #{method_name} << comment
              end

              def root_#{method_name}
                self.#{method_name.singularize}_threads.where(:parent_id => nil)
              end
            }
        end
      end
    end
  end
end

require 'comment_methods'
ActiveRecord::Base.send(:include, Acts::CommentableWithThreading)
