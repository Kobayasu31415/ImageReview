// The imagereview theme. `astryx experimental theme editor` wrote this file once and never changes it again.
// The checked settings live in imagereview.settings.json and the generated imagereview.settings.ts;
// change them with `astryx experimental theme editor set imagereview ...`. Add your own changes below: they win over the settings.
import {defineTheme} from '@astryxdesign/core/theme';
import {imagereviewSettings} from './imagereview.settings';

export const imagereviewTheme = defineTheme({
  extends: imagereviewSettings,
  name: 'imagereview',
});
