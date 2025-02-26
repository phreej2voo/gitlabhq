import {
  CoreV1Api,
  Configuration,
  AppsV1Api,
  BatchV1Api,
  WatchApi,
  EVENT_DATA,
  EVENT_TIMEOUT,
  EVENT_ERROR,
} from '@gitlab/cluster-client';
import { humanizeClusterErrors } from '../../helpers/k8s_integration_helper';
import k8sPodsQuery from '../queries/k8s_pods.query.graphql';

const mapWorkloadItems = (items, kind) => {
  return items.map((item) => {
    const updatedItem = {
      status: {},
      spec: {},
    };

    switch (kind) {
      case 'DeploymentList':
        updatedItem.status.conditions = item.status.conditions || [];
        break;
      case 'DaemonSetList':
        updatedItem.status = {
          numberMisscheduled: item.status.numberMisscheduled || 0,
          numberReady: item.status.numberReady || 0,
          desiredNumberScheduled: item.status.desiredNumberScheduled || 0,
        };
        break;
      case 'StatefulSetList':
      case 'ReplicaSetList':
        updatedItem.status.readyReplicas = item.status.readyReplicas || 0;
        updatedItem.spec.replicas = item.spec.replicas || 0;
        break;
      case 'JobList':
        updatedItem.status.failed = item.status.failed || 0;
        updatedItem.status.succeeded = item.status.succeeded || 0;
        updatedItem.spec.completions = item.spec.completions || 0;
        break;
      case 'CronJobList':
        updatedItem.status.active = item.status.active || 0;
        updatedItem.status.lastScheduleTime = item.status.lastScheduleTime || '';
        updatedItem.spec.suspend = item.spec.suspend || 0;
        break;
      default:
        updatedItem.status = item?.status;
        updatedItem.spec = item?.spec;
        break;
    }

    return updatedItem;
  });
};

const handleClusterError = async (err) => {
  if (!err.response) {
    throw err;
  }

  const errorData = await err.response.json();
  throw errorData;
};

export default {
  k8sPods(_, { configuration, namespace }, { client }) {
    const config = new Configuration(configuration);

    if (!gon.features?.k8sWatchApi) {
      const coreV1Api = new CoreV1Api(config);
      const podsApi = namespace
        ? coreV1Api.listCoreV1NamespacedPod({ namespace })
        : coreV1Api.listCoreV1PodForAllNamespaces();

      return podsApi
        .then((res) => res?.items || [])
        .catch(async (err) => {
          try {
            await handleClusterError(err);
          } catch (error) {
            throw new Error(error.message);
          }
        });
    }

    const path = namespace ? `/api/v1/namespaces/${namespace}/pods` : '/api/v1/pods';
    const watcherApi = new WatchApi(config);

    return watcherApi.subscribeToStream(path, { watch: true }).then((watcher) => {
      let result = [];

      return new Promise((resolve, reject) => {
        watcher.on(EVENT_DATA, (data) => {
          result = data.map((item) => {
            return { status: { phase: item.status.phase } };
          });

          resolve(result);

          setTimeout(() => {
            client.writeQuery({
              query: k8sPodsQuery,
              variables: { configuration, namespace },
              data: { k8sPods: result },
            });
          }, 0);
        });

        watcher.on(EVENT_TIMEOUT, () => {
          resolve(result);
        });

        watcher.on(EVENT_ERROR, (errorData) => {
          const error = errorData?.message ? new Error(errorData.message) : errorData;
          reject(error);
        });
      });
    });
  },
  k8sServices(_, { configuration, namespace }) {
    const coreV1Api = new CoreV1Api(new Configuration(configuration));
    const servicesApi = namespace
      ? coreV1Api.listCoreV1NamespacedService({ namespace })
      : coreV1Api.listCoreV1ServiceForAllNamespaces();

    return servicesApi
      .then((res) => {
        const items = res?.items || [];
        return items.map((item) => {
          const { type, clusterIP, externalIP, ports } = item.spec;
          return {
            metadata: item.metadata,
            spec: {
              type,
              clusterIP: clusterIP || '-',
              externalIP: externalIP || '-',
              ports,
            },
          };
        });
      })
      .catch(async (err) => {
        try {
          await handleClusterError(err);
        } catch (error) {
          throw new Error(error.message);
        }
      });
  },
  k8sWorkloads(_, { configuration, namespace }) {
    const appsV1api = new AppsV1Api(new Configuration(configuration));
    const batchV1api = new BatchV1Api(new Configuration(configuration));

    let promises;

    if (namespace) {
      promises = [
        appsV1api.listAppsV1NamespacedDeployment({ namespace }),
        appsV1api.listAppsV1NamespacedDaemonSet({ namespace }),
        appsV1api.listAppsV1NamespacedStatefulSet({ namespace }),
        appsV1api.listAppsV1NamespacedReplicaSet({ namespace }),
        batchV1api.listBatchV1NamespacedJob({ namespace }),
        batchV1api.listBatchV1NamespacedCronJob({ namespace }),
      ];
    } else {
      promises = [
        appsV1api.listAppsV1DeploymentForAllNamespaces(),
        appsV1api.listAppsV1DaemonSetForAllNamespaces(),
        appsV1api.listAppsV1StatefulSetForAllNamespaces(),
        appsV1api.listAppsV1ReplicaSetForAllNamespaces(),
        batchV1api.listBatchV1JobForAllNamespaces(),
        batchV1api.listBatchV1CronJobForAllNamespaces(),
      ];
    }

    const summaryList = {
      DeploymentList: [],
      DaemonSetList: [],
      StatefulSetList: [],
      ReplicaSetList: [],
      JobList: [],
      CronJobList: [],
    };

    return Promise.allSettled(promises).then(async (results) => {
      if (results.every((res) => res.status === 'rejected')) {
        const error = results[0].reason;
        try {
          await handleClusterError(error);
        } catch (err) {
          throw new Error(err.message);
        }
      }
      for (const promiseResult of results) {
        if (promiseResult.status === 'fulfilled' && promiseResult?.value) {
          const { kind, items } = promiseResult.value;

          if (items?.length > 0) {
            summaryList[kind] = mapWorkloadItems(items, kind);
          }
        }
      }

      return summaryList;
    });
  },
  k8sNamespaces(_, { configuration }) {
    const coreV1Api = new CoreV1Api(new Configuration(configuration));
    const namespacesApi = coreV1Api.listCoreV1Namespace();

    return namespacesApi
      .then((res) => {
        return res?.items || [];
      })
      .catch(async (error) => {
        try {
          await handleClusterError(error);
        } catch (err) {
          throw new Error(humanizeClusterErrors(err.reason));
        }
      });
  },
};
