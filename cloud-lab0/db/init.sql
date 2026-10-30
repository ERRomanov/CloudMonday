-- Создание пользователя и базы для приложения.
-- Запуск (под суперпользователем postgres):
--   psql -U postgres -f db/init.sql

CREATE USER notes_user WITH PASSWORD 'notes_pass';
CREATE DATABASE notes_db OWNER notes_user;
