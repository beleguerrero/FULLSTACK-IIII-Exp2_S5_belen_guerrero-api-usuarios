package cl.duoc.mi_foro_usuarios.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import cl.duoc.mi_foro_usuarios.entity.TipoUsuarioEntity;


@Repository 
public interface TipoUsuarioRespository extends JpaRepository<TipoUsuarioEntity, Long> {

}
