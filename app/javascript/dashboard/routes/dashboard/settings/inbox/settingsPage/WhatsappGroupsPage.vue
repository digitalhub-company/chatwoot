<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import { useStore } from 'dashboard/composables/store';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();
const store = useStore();

const groupsEnabled = ref(Boolean(props.inbox.provider_config?.groups_enabled));
const isToggling = ref(false);
const isCreating = ref(false);
const subject = ref('');
const description = ref('');
const joinApprovalMode = ref('auto_approve');

const approvalOptions = computed(() => [
  {
    value: 'auto_approve',
    label: t('INBOX_MGMT.WHATSAPP_GROUPS.APPROVAL.AUTO'),
  },
  {
    value: 'approval_required',
    label: t('INBOX_MGMT.WHATSAPP_GROUPS.APPROVAL.REQUIRED'),
  },
]);

watch(
  () => props.inbox.provider_config?.groups_enabled,
  value => {
    groupsEnabled.value = Boolean(value);
  }
);

const refreshInbox = async () => {
  await store.dispatch('inboxes/get', props.inbox.id);
};

const handleToggle = async newValue => {
  if (isToggling.value) return;

  const previousValue = groupsEnabled.value;
  groupsEnabled.value = newValue;
  isToggling.value = true;
  try {
    if (newValue) {
      await InboxesAPI.enableWhatsappGroups(props.inbox.id);
    } else {
      await InboxesAPI.disableWhatsappGroups(props.inbox.id);
    }
    await refreshInbox();
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (error) {
    groupsEnabled.value = previousValue;
    useAlert(
      error?.response?.data?.error || t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE')
    );
  } finally {
    isToggling.value = false;
  }
};

const createGroup = async () => {
  if (isCreating.value || !subject.value.trim()) return;

  isCreating.value = true;
  try {
    const response = await InboxesAPI.createWhatsappGroup(props.inbox.id, {
      subject: subject.value.trim(),
      description: description.value.trim(),
      join_approval_mode: joinApprovalMode.value,
    });
    subject.value = '';
    description.value = '';
    useAlert(
      response?.data?.id
        ? t('INBOX_MGMT.WHATSAPP_GROUPS.CREATE_SUCCESS')
        : t('INBOX_MGMT.WHATSAPP_GROUPS.CREATE_ACCEPTED')
    );
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('INBOX_MGMT.WHATSAPP_GROUPS.CREATE_ERROR')
    );
  } finally {
    isCreating.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-6 py-6">
    <SettingsToggleSection
      v-model="groupsEnabled"
      :header="t('INBOX_MGMT.WHATSAPP_GROUPS.ENABLE.LABEL')"
      :description="t('INBOX_MGMT.WHATSAPP_GROUPS.ENABLE.DESCRIPTION')"
      @update:model-value="handleToggle"
    />

    <p class="text-sm text-n-slate-11 px-1">
      {{ t('INBOX_MGMT.WHATSAPP_GROUPS.LIMITS') }}
    </p>

    <form
      v-if="groupsEnabled"
      class="flex flex-col gap-4"
      @submit.prevent="createGroup"
    >
      <SettingsFieldSection
        :label="t('INBOX_MGMT.WHATSAPP_GROUPS.SUBJECT.LABEL')"
      >
        <input
          v-model="subject"
          type="text"
          maxlength="128"
          class="w-full rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm"
          :placeholder="t('INBOX_MGMT.WHATSAPP_GROUPS.SUBJECT.PLACEHOLDER')"
        />
      </SettingsFieldSection>
      <SettingsFieldSection
        :label="t('INBOX_MGMT.WHATSAPP_GROUPS.DESCRIPTION.LABEL')"
        :help-text="t('INBOX_MGMT.WHATSAPP_GROUPS.DESCRIPTION.HELP')"
      >
        <textarea
          v-model="description"
          maxlength="2048"
          rows="3"
          class="w-full rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm"
        />
      </SettingsFieldSection>
      <SettingsFieldSection
        :label="t('INBOX_MGMT.WHATSAPP_GROUPS.APPROVAL.LABEL')"
      >
        <select
          v-model="joinApprovalMode"
          class="w-full rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm"
        >
          <option
            v-for="option in approvalOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
      </SettingsFieldSection>
      <div>
        <NextButton
          type="submit"
          :label="t('INBOX_MGMT.WHATSAPP_GROUPS.CREATE')"
          :is-loading="isCreating"
          :disabled="!subject.trim()"
        />
      </div>
    </form>
  </div>
</template>
