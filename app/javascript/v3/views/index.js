import { createRouter, createWebHistory } from 'vue-router';

import routes from './routes';
import AnalyticsHelper from 'dashboard/helper/AnalyticsHelper';
import { validateRouteAccess } from '../helpers/RouteHelper';

export const router = createRouter({ history: createWebHistory(), routes });

const sensitiveRouteNames = ['auth_password_edit'];

const syncDocumentTitle = () => {
  const installationName = window.globalConfig?.INSTALLATION_NAME;
  if (installationName) {
    document.title = installationName;
  }
};

export const initalizeRouter = () => {
  syncDocumentTitle();

  router.beforeEach((to, _, next) => {
    if (!sensitiveRouteNames.includes(to.name)) {
      AnalyticsHelper.page(to.name || '', {
        path: to.path,
        name: to.name,
      });
    }

    return validateRouteAccess(to, next, window.chatwootConfig);
  });

  router.afterEach(syncDocumentTitle);
};

export default router;
