import axios from 'axios';

// Same-origin: the public booking JSON endpoints live under /public/api/v1.
const API = axios.create({ baseURL: '' });

export const getProfile = async slug => {
  const { data } = await API.get(`/public/api/v1/booking/${slug}`);
  return data;
};

export const getSlots = async (slug, date) => {
  const { data } = await API.get(`/public/api/v1/booking/${slug}/slots`, {
    params: { date },
  });
  return data;
};

export const createBooking = async (slug, payload) => {
  const { data } = await API.post(`/public/api/v1/booking/${slug}`, payload);
  return data;
};

export const confirmBooking = async (slug, token) => {
  const { data } = await API.post(`/public/api/v1/booking/${slug}/confirm`, {
    token,
  });
  return data;
};
