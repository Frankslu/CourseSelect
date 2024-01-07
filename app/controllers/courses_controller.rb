class CoursesController < ApplicationController

  before_action :student_logged_in, only: [:select, :quit, :list]
  before_action :teacher_logged_in, only: [:new, :create, :edit, :destroy, :update, :open, :close]#add open by qiao
  before_action :logged_in, only: :index

  #-------------------------for teachers----------------------

  def new
    @course=Course.new
  end

  def create
    @course = Course.new(course_params)
    if @course.save
      current_user.teaching_courses<<@course
      redirect_to courses_path, flash: {success: "新课程申请成功"}
    else
      flash[:warning] = "信息填写有误,请重试"
      render 'new'
    end
  end

  def edit
    @course=Course.find_by_id(params[:id])
  end

  def update
    @course = Course.find_by_id(params[:id])
    if @course.update_attributes(course_params)
      flash={:info => "更新成功"}
    else
      flash={:warning => "更新失败"}
    end
    redirect_to courses_path, flash: flash
  end

  def open
    @course=Course.find_by_id(params[:id])
    @course.update_attributes(open: true)
    redirect_to courses_path, flash: {:success => "已经成功开启该课程:#{ @course.name}"}
  end

  def close
    @course=Course.find_by_id(params[:id])
    @course.update_attributes(open: false)
    redirect_to courses_path, flash: {:success => "已经成功关闭该课程:#{ @course.name}"}
  end

  def destroy
    @course=Course.find_by_id(params[:id])
    current_user.teaching_courses.delete(@course)
    @course.destroy
    flash={:success => "成功删除课程: #{@course.name}"}
    redirect_to courses_path, flash: flash
  end

  #-------------------------for students----------------------

  def list
    #-------QiaoCode--------
    def course_filter course, key, value
      if value == '' or course[key].include?(value)
        return true
      else
        return false
      end
    end

    if request.post?
      session[:filter] = course_params
    end
    @filter = Course.new(session[:filter])
    @courses = Course.where(open: true)
    @course = @courses-current_user.courses
    tmp=[]
    @course.each do |course|
      condition = course.open==true
      if request.post?
        condition = condition && (course_filter(course, 'course_time', course_params['course_time']) &&
          course_filter(course, 'course_type', course_params['course_type']) &&
          course_filter(course, 'name', course_params['name']))
      elsif session[:filter]
        condition = condition && (course_filter(course, 'course_time', session[:filter]['course_time']) &&
          course_filter(course, 'course_type', session[:filter]['course_type']) &&
          course_filter(course, 'name', session[:filter]['name']))
      end
      if condition==true
        tmp<<course
      end
    end
    @courses = Kaminari.paginate_array(tmp).page(params[:page]).per(4)
  end

  def select
    @course=Course.find_by_id(params[:id])
    if @course.limit_num!=nil and @course.limit_num<=@course.users.count
      flash={:warning => "该课程已经选满"}
      redirect_to list_courses_path, flash: flash
      return
    end
    course_maybe_conflict = current_user.courses.where("course_time LIKE ?", "%#{@course.course_time.split('(').first}%")
    if course_maybe_conflict.count>0
      select_course_time = /\d+\-\d+/.match(@course.course_time).to_s
      select_course_start_time = select_course_time.split('-').first.gsub(/\D/, '').to_i
      select_course_end_time = select_course_time.split('-').last.gsub(/\D/, '').to_i
      course_maybe_conflict.each do |course|
        conflict_time = /\d+\-\d+/.match(course.course_time).to_s
        conflict_start_time = conflict_time.split('-').first.gsub(/\D/, '').to_i
        conflict_end_time = conflict_time.split('-').last.gsub(/\D/, '').to_i
        if select_course_start_time<=conflict_end_time and select_course_end_time>=conflict_start_time
          flash={:warning => "课程时间冲突：#{course.name}, 时间：#{course.course_time}"}
          redirect_to list_courses_path, flash: flash
          return
        end
      end
    end
    current_user.courses<<@course
    @course.update_attributes(student_num: @course.users.count + 1)
    flash = { success: "<span style='color: green;'>成功选择课程: #{@course_name}</span>" }
    redirect_to courses_path, flash: flash
  end

  def quit
    @course=Course.find_by_id(params[:id])
    @course.update_attributes(student_num: @course.users.count - 1)
    current_user.courses.delete(@course)
    flash={:success => "成功退选课程: #{@course.name}"}
    redirect_to courses_path, flash: flash
  end

  def prompt
    public_credit_values = current_user.courses.where("course_type LIKE ?", "%公共%").pluck(:credit)
    @public_credit = public_credit_values.sum { |credit| credit.split("/").last.to_f }
    major_credit_values = current_user.courses.where("course_type NOT LIKE ?", "%公共%").pluck(:credit)
    @major_credit = major_credit_values.sum { |credit| credit.split("/").last.to_f }
    @total_credit = @public_credit + @major_credit
    @total_course = current_user.courses
    @public_course = current_user.courses.where("course_type LIKE ?", "%公共%")
    @major_course = current_user.courses.where("course_type NOT LIKE ?", "%公共%")
  end

  def table
    # course_time内容是周一(1-2)
    @days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
    @times = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12']

    @course_table = {}
    @days.each do |day|
      @course_table[day] = {}
      @times.each do |time|
        @course_table[day][time] = []
      end
    end

    courses = current_user.courses
    courses.each do |course|
      date = /(周.)/.match(course.course_time).to_s
      time = /\d+\-\d+/.match(course.course_time)
      start_time = time.to_s.split('-').first.gsub(/\D/, '')
      end_time = time.to_s.split('-').last.gsub(/\D/, '')
      (start_time.to_i..end_time.to_i).each do |time|
        @course_table[date][time.to_s] << course.name
      end
    end
  end

  #-------------------------for both teachers and students----------------------

  def index
    @course=current_user.teaching_courses.page(params[:page]).per(4) if teacher_logged_in?
    @course=current_user.courses.page(params[:page]).per(4) if student_logged_in?
  end


  private

  # Confirms a student logged-in user.
  def student_logged_in
    unless student_logged_in?
      redirect_to root_url, flash: {danger: '请登陆'}
    end
  end

  # Confirms a teacher logged-in user.
  def teacher_logged_in
    unless teacher_logged_in?
      redirect_to root_url, flash: {danger: '请登陆'}
    end
  end

  # Confirms a  logged-in user.
  def logged_in
    unless logged_in?
      redirect_to root_url, flash: {danger: '请登陆'}
    end
  end

  def course_params
    params.require(:course).permit(:course_code, :name, :course_type, :teaching_type, :exam_type,
                                   :credit, :limit_num, :class_room, :course_time, :course_week)
  end


end
