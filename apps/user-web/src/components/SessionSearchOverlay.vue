<script setup lang="ts">
import { NInput } from 'naive-ui'
import { t } from '../composables/i18n'
import type { SessionSummary, SessionSearchResult } from '../api/sessions'

type SearchItem = SessionSummary | SessionSearchResult

defineProps<{
  open: boolean
  query: string
  trimmedQuery: string
  results: SessionSearchResult[]
  displayItems: SearchItem[]
  loading: boolean
  didRun: boolean
  hasMore: boolean
  currentSessionId: string | null
  editingSessionId: string | null
  editingTitle: string
  renamingSessionId: string | null
  deletingSessionId: string | null
  displaySessionTitle: (session: SearchItem) => string
  compactSessionTitle: (session: SearchItem, limit?: number) => string
  sessionNeedsHumanAssistance: (id: string) => boolean
  sessionScheduledIsRunning: (id: string) => boolean
  sessionIsRunning: (id: string) => boolean
  sessionIsUnread: (id: string) => boolean
}>()
const emit = defineEmits<{
  (e: 'close'): void
  (e: 'update:query', value: string): void
  (e: 'update:editing-title', value: string): void
  (e: 'new-session'): void
  (e: 'select-session', id: string): void
  (e: 'edit-session', session: SearchItem): void
  (e: 'commit-title', session: SearchItem): void
  (e: 'cancel-title'): void
  (e: 'delete-session', id: string): void
  (e: 'load-more'): void
}>()
</script>

<template>
            <div
              v-if="open"
              class="absolute inset-0 z-20 flex items-start justify-center bg-white/45 backdrop-blur-[2px] px-6 pt-20"
              @click.self="emit('close')"
            >
              <div class="w-full max-w-[720px] overflow-hidden rounded-[28px] border border-gray-200 bg-white shadow-[0_24px_80px_rgba(15,23,42,0.12)]">
                <div class="flex items-center gap-3 border-b border-gray-100 px-6 py-5">
                  <n-input
                    :value="query" @update:value="value => emit('update:query', value)"
                    clearable
                    :placeholder="t('app.search.placeholder')"
                    size="large"
                    class="flex-1"
                  />
                  <button
                    class="shrink-0 rounded-full p-2 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-700"
                    @click="emit('close')"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
                  </button>
                </div>
                <div class="max-h-[60vh] overflow-y-auto px-3 py-3 custom-scrollbar">
                  <button
                    class="mb-3 flex w-full items-center gap-3 rounded-2xl bg-gray-50 px-5 py-4 text-left text-gray-700 transition-colors hover:bg-gray-100"
                    @click="emit('new-session')"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14"/><path d="M5 12h14"/></svg>
                    <span class="text-base font-medium">{{ t('app.sidebar.new_chat') }}</span>
                  </button>

                  <div v-if="!trimmedQuery" class="px-4 py-2 text-xs font-semibold uppercase tracking-[0.12em] text-gray-400">
                    {{ t('app.search.recent') }}
                  </div>
                  <div
                    v-else-if="loading && !results.length"
                    class="px-4 py-8 text-center text-sm italic text-gray-400"
                  >
                    {{ t('app.search.searching') }}
                  </div>
                  <div
                    v-else-if="didRun && !results.length"
                    class="px-4 py-8 text-center text-sm italic text-gray-400"
                  >
                    {{ t('app.search.no_results') }}
                  </div>

                  <div
                    v-for="session in displayItems"
                    :key="session.id"
                    class="group flex w-full items-center gap-3 rounded-2xl px-4 py-3 text-left transition-colors"
                    :class="session.id === currentSessionId
                      ? 'bg-gray-100 text-gray-900'
                      : 'text-gray-700 hover:bg-gray-50'"
                    @click="editingSessionId !== session.id && emit('select-session', session.id)"
                    @keydown.enter.prevent="editingSessionId !== session.id && emit('select-session', session.id)"
                    @keydown.space.prevent="editingSessionId !== session.id && emit('select-session', session.id)"
                    role="button"
                    tabindex="0"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="shrink-0 text-gray-400"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
                    <n-input
                      v-if="editingSessionId === session.id"
                      :value="editingTitle" @update:value="value => emit('update:editing-title', value)"
                      size="small"
                      class="min-w-0 flex-1"
                      :data-session-title-input="session.id"
                      :disabled="renamingSessionId === session.id"
                      @click.stop
                      @dblclick.stop
                      @blur="emit('commit-title', session)"
                      @keydown.enter.prevent="emit('commit-title', session)"
                      @keydown.esc.prevent="emit('cancel-title')"
                    />
                    <span
                      v-else
                      class="min-w-0 flex-1 truncate text-base"
                      :title="displaySessionTitle(session)"
                      @dblclick.stop="emit('edit-session', session)"
                    >
                      {{ compactSessionTitle(session, 44) }}
                    </span>
                    <span
                      v-if="sessionNeedsHumanAssistance(session.id)"
                      class="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-semibold text-amber-700"
                      :aria-label="t('app.sidebar.session_needs_assistance')"
                      :title="t('app.sidebar.session_needs_assistance')"
                    >
                      {{ t('app.sidebar.session_needs_assistance_short') }}
                    </span>
                    <span
                      v-else-if="sessionScheduledIsRunning(session.id)"
                      class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-blue-50 text-blue-600"
                      :aria-label="t('projectDialog.scheduledRunning')"
                      :title="t('projectDialog.scheduledRunning')"
                    >
                      <svg viewBox="0 0 24 24" class="h-3.5 w-3.5 animate-pulse" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>
                    </span>
                    <span
                      v-else-if="sessionIsRunning(session.id)"
                      class="h-2 w-2 shrink-0 rounded-full bg-blue-500 animate-pulse"
                      :aria-label="t('app.sidebar.session_running')"
                      :title="t('app.sidebar.session_running')"
                    ></span>
                    <span
                      v-else-if="sessionIsUnread(session.id)"
                      class="h-2 w-2 shrink-0 rounded-full bg-blue-500"
                      :aria-label="t('app.sidebar.session_unread')"
                      :title="t('app.sidebar.session_unread')"
                    ></span>
                    <button
                      type="button"
                      class="h-6 shrink-0 overflow-hidden rounded-md p-0 text-gray-400 opacity-0 transition-all hover:bg-gray-100 hover:text-red-500 group-hover:w-6 group-hover:p-1 group-hover:opacity-100"
                      :class="deletingSessionId === session.id ? 'w-6 !p-1 !opacity-100 text-red-500' : 'w-0'"
                      :disabled="deletingSessionId === session.id"
                      @click.stop="emit('delete-session', session.id)"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg>
                    </button>
                  </div>

                  <button
                    v-if="trimmedQuery && didRun && hasMore"
                    class="mt-3 w-full rounded-xl border border-gray-200 px-3 py-2 text-sm text-gray-600 transition-colors hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-60"
                    :disabled="loading"
                    @click="emit('load-more')"
                  >
                    {{ loading ? t('app.search.searching') : t('app.search.load_more_results') }}
                  </button>
                </div>
              </div>
            </div>
</template>
