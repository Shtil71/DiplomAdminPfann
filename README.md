# Дипломная работа по профессии «Системный администратор»/ Пфанненштиль Е.С
# Задача
Ключевая задача — разработать отказоустойчивую инфраструктуру для сайта, включающую мониторинг, сбор логов и резервное копирование основных данных. Инфраструктура должна размещаться в Yandex Cloud и отвечать минимальным стандартам безопасности: запрещается выкладывать токен от облака в git.

#  АДРЕСА ДЛЯ ПРОВЕРКИ РАБОТЫ
Сайт - http://158.160.187.194
zabbix - http://51.250.88.131/zabbix
Kibana - http://158.160.34.209:5601 (возможны падения, из-за санкций и геопозиции)

# Инфраструктура

Для развёртки инфраструктуры используем Terraform, а для установки ПО Ansible.

## Terraform
Используем заранее написанный файл и активируем его через 
terraform apply
При помощи Terraform сразу создается Сеть, ВМ, Резервное копирование
<img width="1280" height="776" alt="image" src="https://github.com/user-attachments/assets/4adb4825-0eb1-4b6b-8887-e18406f4200a" />

Проверяем что все создано корректно и переходим к Ansible.
В ansible я постарался максимальное количество ПО установить одним запуском playbook для того, чтобы сделать систему более простой и индепатентной
<img width="1135" height="1280" alt="image" src="https://github.com/user-attachments/assets/7050db44-db22-4426-adc1-0ad7c36a4b51" />

Дожидаемся отработки плейбука и проверяем все созданные ресурсы
<img width="1280" height="687" alt="image" src="https://github.com/user-attachments/assets/d33dcbcb-b7e1-48c6-acf5-7a74c6884817" />
<img width="1280" height="626" alt="image" src="https://github.com/user-attachments/assets/72735b35-2ad5-40a2-8c8c-357ca3be47b9" />
<img width="1280" height="195" alt="image" src="https://github.com/user-attachments/assets/ac26a97e-933c-4035-b4bc-08480a81ba14" />


<img width="2872" height="1507" alt="image" src="https://github.com/user-attachments/assets/550b489f-d46e-4189-9ab8-81c3208d76c5" />

<img width="2879" height="1546" alt="image" src="https://github.com/user-attachments/assets/ee27b286-09c6-4021-9cc8-480854971737" />
<img width="1842" height="654" alt="image" src="https://github.com/user-attachments/assets/ff0bf9a4-bd38-4b23-a9c0-133ffaed636a" />

Надеюсь, что работа удовлетворяет минимальным требованиям. Благодарю за проверку.
