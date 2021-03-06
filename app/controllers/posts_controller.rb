require_dependency 'post_creator'

class PostsController < ApplicationController

  # Need to be logged in for all actions here
  before_filter :ensure_logged_in, except: [:show, :replies, :by_number]


  def create
    requires_parameter(:post)

    post_creator = PostCreator.new(current_user,
                                   raw: params[:post][:raw],
                                   topic_id: params[:post][:topic_id],
                                   title: params[:title],
                                   archetype: params[:archetype],
                                   category: params[:post][:category],
                                   target_usernames: params[:target_usernames],
                                   reply_to_post_number: params[:post][:reply_to_post_number],
                                   image_sizes: params[:image_sizes],
                                   meta_data: params[:meta_data])
    post = post_creator.create

    if post_creator.errors.present?
      render_json_error(post_creator)
    else
      post_serializer = PostSerializer.new(post, scope: guardian, root: false)
      post_serializer.topic_slug = post.topic.slug if post.topic.present?
      post_serializer.draft_sequence = DraftSequence.current(current_user, post.topic.draft_key)
      render_json_dump(post_serializer)
    end

  end

  def update
    requires_parameter(:post)

    @post = Post.where(id: params[:id]).first
    @post.image_sizes = params[:image_sizes] if params[:image_sizes].present?
    guardian.ensure_can_edit!(@post)
    if @post.revise(current_user, params[:post][:raw])
      TopicLink.extract_from(@post)
    end

    if @post.errors.present?
      render_json_error(@post)
      return
    end

    post_serializer = PostSerializer.new(@post, scope: guardian, root: false)
    post_serializer.draft_sequence = DraftSequence.current(current_user, @post.topic.draft_key)
    link_counts = TopicLinkClick.counts_for(@post.topic, [@post])
    post_serializer.single_post_link_counts = link_counts[@post.id] if link_counts.present?
    render_json_dump(post_serializer)
  end

  def by_number
    @post = Post.where(topic_id: params[:topic_id], post_number: params[:post_number]).first
    guardian.ensure_can_see!(@post)
    @post.revert_to(params[:version].to_i) if params[:version].present?
    post_serializer = PostSerializer.new(@post, scope: guardian, root: false)
    post_serializer.add_raw = true
    render_json_dump(post_serializer)
  end

  def show
    @post = Post.where(id: params[:id]).first
    guardian.ensure_can_see!(@post)

    @post.revert_to(params[:version].to_i) if params[:version].present?
    post_serializer = PostSerializer.new(@post, scope: guardian, root: false)
    post_serializer.add_raw = true
    render_json_dump(post_serializer)
  end

  def destroy
    Post.transaction do
      post = Post.with_deleted.where(id: params[:id]).first
      guardian.ensure_can_delete!(post)
      if post.deleted_at.nil?
        post.destroy
      else
        post.recover
      end
      Topic.reset_highest(post.topic_id)
    end
    render nothing: true
  end

  def destroy_many

    requires_parameters(:post_ids)

    posts = Post.where(id: params[:post_ids])
    raise Discourse::InvalidParameters.new(:post_ids) if posts.blank?

    # Make sure we can delete the posts
    posts.each {|p| guardian.ensure_can_delete!(p) }

    Post.transaction do
      topic_id = posts.first.topic_id
      posts.each {|p| p.destroy }
      Topic.reset_highest(topic_id)
    end

    render nothing: true
  end

  # Retrieves a list of versions and who made them for a post
  def versions
    post = Post.where(id: params[:post_id]).first
    guardian.ensure_can_see!(post)

    render_serialized(post.all_versions, VersionSerializer)
  end

  # Direct replies to this post
  def replies
    post = Post.where(id: params[:post_id]).first
    guardian.ensure_can_see!(post)
    render_serialized(post.replies, PostSerializer)
  end


  def bookmark
    post = Post.where(id: params[:post_id]).first
    guardian.ensure_can_see!(post)
    if current_user
      if params[:bookmarked] == "true"
        PostAction.act(current_user, post, PostActionType.Types[:bookmark])
      else
        PostAction.remove_act(current_user, post, PostActionType.Types[:bookmark])
      end
    end
    render :nothing => true
  end

end
