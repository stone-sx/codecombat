require('app/styles/teachers/edit-student-modal.sass')
ModalView = require 'views/core/ModalView'
State = require 'models/State'
Prepaids = require 'collections/Prepaids'
template = require 'templates/teachers/edit-student-modal'
auth = require 'core/auth'

module.exports = class EditStudentModal extends ModalView
  id: 'edit-student-modal'
  template: template

  events:
    'click .send-recovery-email-btn:not(.disabled)': 'onClickSendRecoveryEmail'
    'click .change-password-btn:not(.disabled)': 'onClickChangePassword'
    'click .revoke-student-btn': 'onClickRevokeStudentButton'
    'click .enroll-student-btn:not(.disabled)': 'onClickEnrollStudentButton'
    'input .new-password-input': 'onChangeNewPasswordInput'

  initialize: ({ @user, @classroom }) ->
    @supermodel.trackRequest @user.fetch()
    @utils = require 'core/utils'
    @state = new State({
      emailSent: false
      passwordChanged: false
      newPassword: ""
      errorMessage: ""
    })
    @prepaids = new Prepaids()
    @prepaids.comparator = 'endDate'
    @supermodel.trackRequest @prepaids.fetchMineAndShared()
    @listenTo @state, 'change', @render
    @listenTo @classroom, 'save-password:success', ->
      @state.set { passwordChanged: true, errorMessage: "" }
    @listenTo @classroom, 'save-password:error', (error) ->
      @state.set({ errorMessage: error.message })
      # TODO: Show an error. (password too short)

  onClickSendRecoveryEmail: ->
    email = @user.get('email')
    auth.sendRecoveryEmail(email).then =>
      @state.set { emailSent: true }

  onClickRevokeStudentButton: (e) ->
    button = $(e.currentTarget)
    s = $.i18n.t('teacher.revoke_confirm').replace('{{student_name}}', @user.broadName())
    return unless confirm(s)
    prepaid = @user.makeCoursePrepaid()
    button.text($.i18n.t('teacher.revoking'))
    prepaid.revoke(@user, {
      success: =>
        @user.unset('coursePrepaid')
        @prepaids.fetchMineAndShared().done(=> @render())
      error: (prepaid, jqxhr) =>
        msg = jqxhr.responseJSON.message
        noty text: msg, layout: 'center', type: 'error', killer: true, timeout: 3000
    })

  # TODO: Same logic as in `TeacherClassView.coffee`
  studentStatusString: (student) ->
    status = student.prepaidStatus()
    expires = student.get('coursePrepaid')?.endDate
    string = switch status
      when 'not-enrolled' then $.i18n.t('teacher.status_not_enrolled')
      when 'enrolled' then (if expires then $.i18n.t('teacher.status_enrolled') else '-')
      when 'expired' then $.i18n.t('teacher.status_expired')
    return string.replace('{{date}}', moment(expires).utc().format('ll'))

  onClickEnrollStudentButton: ->
    return unless me.id is @classroom.get('ownerID')
    prepaid = @prepaids.find((prepaid) -> prepaid.status() is 'available')
    prepaid.redeem(@user, {
      success: (prepaid) =>
        @user.set('coursePrepaid', prepaid.pick('_id', 'startDate', 'endDate', 'type', 'includedCourseIDs'))
      error: (prepaid, jqxhr) =>
        msg = jqxhr.responseJSON.message
        noty text: msg, layout: 'center', type: 'error', killer: true, timeout: 3000
      complete: => 
        @render()
    })

  onClickChangePassword: ->
    @classroom.setStudentPassword(@user, @state.get('newPassword'))

  onChangeNewPasswordInput: (e) ->
    @state.set { 
      newPassword: $(e.currentTarget).val()
      emailSent: false
      passwordChanged: false
    }, { silent: true }
    @renderSelectors('.change-password-btn')
